import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/core/utils/inpaint_mask_utils.dart';
import 'package:nai_launcher/data/datasources/remote/nai_image_generation_api_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/image/image_stream_chunk.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_command.dart';
import 'package:nai_launcher/presentation/providers/generation/image_generation_coordinator.dart';

class _MockNAIImageGenerationApiService extends Mock
    implements NAIImageGenerationApiService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ImageParams());
  });

  test(
    'a fixed seed starts a multi-image run and advances by batch size',
    () async {
      final api = _MockNAIImageGenerationApiService();
      final sentSeeds = <int>[];
      when(
        () => api.generateImageWithEncodingsCancellable(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((invocation) async {
        final params = invocation.positionalArguments.single as ImageParams;
        sentSeeds.add(params.seed);
        return (
          [
            for (var i = 0; i < params.nSamples; i++)
              Uint8List.fromList([i + 1]),
          ],
          <int, String>{},
        );
      });
      final coordinator = ImageGenerationCoordinator(apiService: api);
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test', seed: 42),
        batchCount: 2,
        batchSize: 2,
        prepareBatch: (_, params) async => params,
        streamPreviewEnabled: false,
        firstRandomSeed: 12345,
      );
      final events = await coordinator
          .execute(command, coordinator.start(command))
          .toList();

      expect(sentSeeds, [42, 44]);
      expect(
        events.whereType<GenerationRequestStarted>().map(
          (event) => event.params.seed,
        ),
        sentSeeds,
      );
      expect(events.last, isA<GenerationCompleted>());
    },
  );

  test('prepareBatch exceptions become terminal failure events', () async {
    final apiService = _MockNAIImageGenerationApiService();
    final coordinator = ImageGenerationCoordinator(apiService: apiService);
    final command = GenerationCommand(
      runId: 1,
      params: const ImageParams(prompt: 'test'),
      batchCount: 1,
      batchSize: 1,
      prepareBatch: (_, _) =>
          Future<ImageParams>.error(StateError('prepareBatch failed')),
    );
    final handle = coordinator.start(command);

    final events = await coordinator.execute(command, handle).toList();

    expect(events, hasLength(2));
    expect(events.first, isA<GenerationStarted>());
    expect(events.last, isA<GenerationFailed>());
    expect(
      (events.last as GenerationFailed).error.toString(),
      contains('prepareBatch failed'),
    );
    verifyNever(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    );
  });

  test(
    'disabled stream preview uses the non-stream endpoint directly',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      final image = Uint8List.fromList([1, 2, 3]);
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) async => (<Uint8List>[image], <int, String>{}));

      final coordinator = ImageGenerationCoordinator(apiService: apiService);
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 1,
        prepareBatch: (_, params) async => params,
        streamPreviewEnabled: false,
      );
      final handle = coordinator.start(command);

      final events = await coordinator.execute(command, handle).toList();

      expect(events.whereType<GenerationPreviewReceived>(), isEmpty);
      expect(events.whereType<GenerationRequestCompleted>(), hasLength(1));
      expect(events.last, isA<GenerationCompleted>());
      verifyNever(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      );
      verify(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(1);
    },
  );

  test('cancel interrupts an injected 429 concurrency retry delay', () async {
    final apiService = _MockNAIImageGenerationApiService();
    final delayStarted = Completer<void>();
    final blockedDelay = Completer<void>();
    when(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer((_) => Stream.value(ImageStreamChunk.error('API_ERROR_429')));
    when(() => apiService.cancelGeneration(any())).thenReturn(null);

    final coordinator = ImageGenerationCoordinator(
      apiService: apiService,
      delay: (_) {
        if (!delayStarted.isCompleted) delayStarted.complete();
        return blockedDelay.future;
      },
    );
    final command = GenerationCommand(
      runId: 1,
      params: const ImageParams(prompt: 'test'),
      batchCount: 1,
      batchSize: 1,
      prepareBatch: (_, params) async => params,
    );
    final handle = coordinator.start(command);
    final events = coordinator.execute(command, handle).toList();

    await delayStarted.future;
    coordinator.cancel(handle);

    final completedEvents = await events.timeout(const Duration(seconds: 1));
    expect(completedEvents.last, isA<GenerationCancelled>());
    expect(blockedDelay.isCompleted, isFalse);
    blockedDelay.complete();
  });

  test(
    'cancel before an empty stream ends prevents fallback request',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      final streamStarted = Completer<void>();
      final stream = StreamController<ImageStreamChunk>(
        onListen: streamStarted.complete,
      );
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) => stream.stream);
      when(() => apiService.cancelGeneration(any())).thenReturn(null);

      final coordinator = ImageGenerationCoordinator(apiService: apiService);
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 1,
        prepareBatch: (_, params) async => params,
        cancellableFallback: false,
      );
      final handle = coordinator.start(command);
      final events = coordinator.execute(command, handle).toList();

      await streamStarted.future;
      coordinator.cancel(handle);
      await stream.close();

      final completedEvents = await events.timeout(const Duration(seconds: 1));
      expect(completedEvents.last, isA<GenerationCancelled>());
      verifyNever(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      );
    },
  );

  test(
    'cancel as an empty stream finishes prevents fallback request',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      final streamStarted = Completer<void>();
      final streamEnded = Completer<void>();
      late final ImageGenerationCoordinator coordinator;
      late final GenerationRunHandle handle;
      final stream = StreamController<ImageStreamChunk>(
        onListen: streamStarted.complete,
        onCancel: () {
          coordinator.cancel(handle);
          streamEnded.complete();
        },
      );
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) => stream.stream);
      when(() => apiService.cancelGeneration(any())).thenReturn(null);

      coordinator = ImageGenerationCoordinator(apiService: apiService);
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 1,
        prepareBatch: (_, params) async => params,
        cancellableFallback: false,
      );
      handle = coordinator.start(command);
      final events = coordinator.execute(command, handle).toList();

      await streamStarted.future;
      await stream.close();
      await streamEnded.future.timeout(const Duration(seconds: 1));

      final completedEvents = await events.timeout(const Duration(seconds: 1));
      expect(completedEvents.last, isA<GenerationCancelled>());
      verifyNever(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      );
    },
  );

  test('multi-image stream fallback preserves vibe encodings', () async {
    final apiService = _MockNAIImageGenerationApiService();
    final images = <Uint8List>[
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5, 6]),
    ];
    const encodings = <int, String>{0: 'vibe-encoding'};
    when(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer(
      (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
    );
    when(
      () => apiService.generateImageWithEncodingsCancellable(
        any(),
        onProgress: any(named: 'onProgress'),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer((_) async => (images, encodings));

    final coordinator = ImageGenerationCoordinator(apiService: apiService);
    final command = GenerationCommand(
      runId: 1,
      params: const ImageParams(prompt: 'test', seed: 42),
      batchCount: 1,
      batchSize: 2,
      prepareBatch: (_, params) async => params,
      materializeRandomSeed: false,
    );
    final handle = coordinator.start(command);

    final events = await coordinator.execute(command, handle).toList();

    final requestCompleted = events
        .whereType<GenerationRequestCompleted>()
        .single;
    final completed = events.whereType<GenerationCompleted>().single;
    expect(requestCompleted.images, images);
    expect(requestCompleted.vibeEncodings, encodings);
    expect(completed.images, images);
    final streamParams =
        verify(
              () => apiService.generateImageStream(
                captureAny(),
                focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
                minimumContextMegaPixels: any(
                  named: 'minimumContextMegaPixels',
                ),
                focusedSelectionRect: any(named: 'focusedSelectionRect'),
              ),
            ).captured.single
            as ImageParams;
    final fallbackParams =
        verify(
              () => apiService.generateImageWithEncodingsCancellable(
                captureAny(),
                onProgress: any(named: 'onProgress'),
                focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
                minimumContextMegaPixels: any(
                  named: 'minimumContextMegaPixels',
                ),
                focusedSelectionRect: any(named: 'focusedSelectionRect'),
              ),
            ).captured.single
            as ImageParams;
    expect(streamParams.seed, 42);
    expect(fallbackParams.seed, 42);
    expect(streamParams.nSamples, 2);
    expect(fallbackParams.nSamples, 2);
  });

  test('cancel interrupts multi-image fallback with encodings', () async {
    final apiService = _MockNAIImageGenerationApiService();
    final fallbackStarted = Completer<void>();
    final fallbackResult = Completer<(List<Uint8List>, Map<int, String>)>();
    when(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer(
      (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
    );
    when(
      () => apiService.generateImageWithEncodingsCancellable(
        any(),
        onProgress: any(named: 'onProgress'),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer((_) {
      fallbackStarted.complete();
      return fallbackResult.future;
    });
    when(() => apiService.cancelGeneration(any())).thenAnswer((_) {
      fallbackResult.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/generate-image'),
          type: DioExceptionType.cancel,
        ),
      );
    });

    final coordinator = ImageGenerationCoordinator(apiService: apiService);
    final command = GenerationCommand(
      runId: 1,
      params: const ImageParams(prompt: 'test'),
      batchCount: 1,
      batchSize: 2,
      prepareBatch: (_, params) async => params,
    );
    final handle = coordinator.start(command);
    final events = coordinator.execute(command, handle).toList();

    await fallbackStarted.future;
    coordinator.cancel(handle);

    final completedEvents = await events.timeout(const Duration(seconds: 1));
    expect(completedEvents.last, isA<GenerationCancelled>());
    expect(completedEvents, isNot(contains(isA<GenerationRequestCompleted>())));
    verify(() => apiService.cancelGeneration(any())).called(1);
  });

  test(
    'streaming-not-allowed fallback retries ordinary failures and succeeds',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      final delays = <Duration>[];
      var fallbackCalls = 0;
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer(
        (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
      );
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) async {
        fallbackCalls++;
        if (fallbackCalls < 4) throw StateError('temporary fallback failure');
        return (
          <Uint8List>[
            Uint8List.fromList([4]),
          ],
          <int, String>{2: 'fallback-vibe'},
        );
      });

      final coordinator = ImageGenerationCoordinator(
        apiService: apiService,
        delay: (duration) async => delays.add(duration),
      );
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 1,
        prepareBatch: (_, params) async => params,
        materializeRandomSeed: false,
        cancellableFallback: false,
      );
      final handle = coordinator.start(command);

      final events = await coordinator.execute(command, handle).toList();
      final completed = events.whereType<GenerationRequestCompleted>().single;

      expect(
        events.whereType<GenerationRetrying>().map((event) => event.attempt),
        [1, 2, 3],
      );
      expect(fallbackCalls, 4);
      expect(delays, isEmpty, reason: 'failed requests retry at once');
      expect(completed.images.single, Uint8List.fromList([4]));
      expect(completed.vibeEncodings, {2: 'fallback-vibe'});
      verify(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(1);
    },
  );

  test(
    'streaming-not-allowed fallback waits out 429 without using retries',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      final delays = <Duration>[];
      var fallbackCalls = 0;
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer(
        (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
      );
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) async {
        fallbackCalls++;
        if (fallbackCalls < 4) {
          throw DioException(
            requestOptions: RequestOptions(path: '/generate-image'),
            response: Response<void>(
              requestOptions: RequestOptions(path: '/generate-image'),
              statusCode: 429,
            ),
          );
        }
        return (
          <Uint8List>[
            Uint8List.fromList([9]),
          ],
          <int, String>{},
        );
      });

      final coordinator = ImageGenerationCoordinator(
        apiService: apiService,
        delay: (duration) async => delays.add(duration),
      );
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 1,
        prepareBatch: (_, params) async => params,
        materializeRandomSeed: false,
        cancellableFallback: false,
      );
      final handle = coordinator.start(command);

      final events = await coordinator.execute(command, handle).toList();

      expect(events.last, isA<GenerationCompleted>());
      expect(fallbackCalls, 4);
      expect(delays, const [
        Duration(seconds: 3),
        Duration(seconds: 3),
        Duration(seconds: 3),
      ]);
      expect(events.whereType<GenerationRetrying>(), isEmpty);
      verify(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(1);
    },
  );

  test('cancel after a failed attempt prevents another request', () async {
    final apiService = _MockNAIImageGenerationApiService();
    late ImageGenerationCoordinator coordinator;
    late GenerationRunHandle handle;
    when(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer(
      (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
    );
    when(
      () => apiService.generateImage(
        any(),
        onProgress: any(named: 'onProgress'),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer((_) async {
      coordinator.cancel(handle);
      throw StateError('temporary fallback failure');
    });
    when(() => apiService.cancelGeneration(any())).thenReturn(null);

    coordinator = ImageGenerationCoordinator(apiService: apiService);
    final command = GenerationCommand(
      runId: 1,
      params: const ImageParams(prompt: 'test'),
      batchCount: 1,
      batchSize: 1,
      prepareBatch: (_, params) async => params,
      materializeRandomSeed: false,
      cancellableFallback: false,
    );
    handle = coordinator.start(command);

    final events = await coordinator
        .execute(command, handle)
        .toList()
        .timeout(const Duration(seconds: 1));

    expect(events.last, isA<GenerationCancelled>());
    expect(events.whereType<GenerationRetrying>(), isEmpty);
    verify(
      () => apiService.generateImage(
        any(),
        onProgress: any(named: 'onProgress'),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).called(1);
  });

  test('exhausted fallback retries fail without returning to stream', () async {
    final apiService = _MockNAIImageGenerationApiService();
    final delays = <Duration>[];
    when(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer(
      (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
    );
    when(
      () => apiService.generateImage(
        any(),
        onProgress: any(named: 'onProgress'),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenThrow(StateError('persistent fallback failure'));

    final coordinator = ImageGenerationCoordinator(
      apiService: apiService,
      delay: (duration) async => delays.add(duration),
    );
    final command = GenerationCommand(
      runId: 1,
      params: const ImageParams(prompt: 'test'),
      batchCount: 1,
      batchSize: 1,
      prepareBatch: (_, params) async => params,
      materializeRandomSeed: false,
      cancellableFallback: false,
    );
    final handle = coordinator.start(command);

    final events = await coordinator.execute(command, handle).toList();

    expect(events.whereType<GenerationRequestFailed>(), hasLength(1));
    expect(events.last, isA<GenerationFailed>());
    expect(
      (events.last as GenerationFailed).error.toString(),
      contains('persistent fallback failure'),
    );
    expect(delays, isEmpty);
    expect(
      events.whereType<GenerationRetrying>().map((event) => event.attempt),
      [1, 2, 3, 4, 5],
    );
    verify(
      () => apiService.generateImage(
        any(),
        onProgress: any(named: 'onProgress'),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).called(6);
    verify(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).called(1);
  });

  test(
    'per-image requests retain global image indexes for every slot',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      var fallbackCall = 0;
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer(
        (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
      );
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) async {
        fallbackCall++;
        return (
          <Uint8List>[
            Uint8List.fromList([fallbackCall]),
          ],
          <int, String>{
            0: 'image-$fallbackCall-slot-0',
            2: 'image-$fallbackCall-slot-2',
          },
        );
      });

      final coordinator = ImageGenerationCoordinator(apiService: apiService);
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test', seed: 10),
        batchCount: 1,
        batchSize: 2,
        prepareBatch: (_, params) async => params,
        materializeRandomSeed: false,
        requestEachImage: true,
        cancellableFallback: false,
      );
      final handle = coordinator.start(command);

      final completed = (await coordinator.execute(command, handle).toList())
          .whereType<GenerationRequestCompleted>()
          .single;

      expect(completed.images, hasLength(2));
      expect(
        completed.indexedVibeEncodings
            .map(
              (entry) => '${entry.imageIndex}_${entry.slot}:${entry.encoding}',
            )
            .toList(),
        [
          '1_0:image-1-slot-0',
          '1_2:image-1-slot-2',
          '2_0:image-2-slot-0',
          '2_2:image-2-slot-2',
        ],
      );
      verify(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(2);
    },
  );

  test(
    'cancel stops per-image fallback without publishing partial encodings',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      final secondFallbackStarted = Completer<void>();
      final secondFallback = Completer<(List<Uint8List>, Map<int, String>)>();
      var fallbackCall = 0;
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer(
        (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
      );
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) {
        fallbackCall++;
        if (fallbackCall == 1) {
          return Future.value((
            <Uint8List>[
              Uint8List.fromList([1]),
            ],
            <int, String>{0: 'first'},
          ));
        }
        secondFallbackStarted.complete();
        return secondFallback.future;
      });
      when(() => apiService.cancelGeneration(any())).thenAnswer((_) {
        secondFallback.completeError(StateError('cancelled locally'));
      });

      final coordinator = ImageGenerationCoordinator(apiService: apiService);
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 2,
        prepareBatch: (_, params) async => params,
        requestEachImage: true,
        cancellableFallback: false,
      );
      final handle = coordinator.start(command);
      final events = coordinator.execute(command, handle).toList();

      await secondFallbackStarted.future;
      coordinator.cancel(handle);
      final completedEvents = await events.timeout(const Duration(seconds: 1));

      expect(completedEvents.last, isA<GenerationCancelled>());
      expect(
        completedEvents,
        isNot(contains(isA<GenerationRequestCompleted>())),
      );
      verify(() => apiService.cancelGeneration(any())).called(1);
    },
  );

  test('the final chunk finalizes instead of posing as a preview', () async {
    final apiService = _MockNAIImageGenerationApiService();
    final preview = Uint8List.fromList([1, 2, 3]);
    final finalImage = Uint8List.fromList([4, 5, 6]);
    when(
      () => apiService.generateImageStream(
        any(),
        focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
        minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
        focusedSelectionRect: any(named: 'focusedSelectionRect'),
      ),
    ).thenAnswer(
      (_) => Stream<ImageStreamChunk>.fromIterable([
        ImageStreamChunk.progress(progress: 0.5, previewImage: preview),
        ImageStreamChunk.complete(finalImage),
      ]),
    );

    final coordinator = ImageGenerationCoordinator(apiService: apiService);
    final command = GenerationCommand(
      runId: 1,
      params: const ImageParams(prompt: 'test'),
      batchCount: 1,
      batchSize: 1,
      prepareBatch: (_, params) async => params,
    );
    final handle = coordinator.start(command);

    final events = await coordinator.execute(command, handle).toList();

    final previews = events.whereType<GenerationPreviewReceived>().toList();
    expect(previews, hasLength(1));
    expect(previews.single.progress, lessThan(1));
    final finalizing = events.whereType<GenerationImageFinalizing>().single;
    expect(finalizing.imageNumber, 1);
    expect(finalizing.totalImages, 1);
    expect(
      events.whereType<GenerationRequestCompleted>().single.images.single,
      same(finalImage),
    );
  });

  test(
    'shared request keeps slot map semantics without image indexes',
    () async {
      final apiService = _MockNAIImageGenerationApiService();
      final images = <Uint8List>[
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ];
      const encodings = <int, String>{0: 'shared-0', 2: 'shared-2'};
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer(
        (_) => Stream.value(ImageStreamChunk.error('Streaming is not allowed')),
      );
      when(
        () => apiService.generateImageWithEncodingsCancellable(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) async => (images, encodings));

      final coordinator = ImageGenerationCoordinator(apiService: apiService);
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 2,
        prepareBatch: (_, params) async => params,
      );
      final handle = coordinator.start(command);

      final completed = (await coordinator.execute(command, handle).toList())
          .whereType<GenerationRequestCompleted>()
          .single;

      expect(completed.vibeEncodings, encodings);
      expect(completed.indexedVibeEncodings, isEmpty);
    },
  );

  group('fixed retries', () {
    late _MockNAIImageGenerationApiService apiService;
    late List<Duration> delays;
    late List<ImageStreamChunk> Function(int call) streamReplies;
    var streamCalls = 0;

    setUp(() {
      apiService = _MockNAIImageGenerationApiService();
      delays = [];
      streamCalls = 0;
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer((_) => Stream.fromIterable(streamReplies(++streamCalls)));
    });

    Future<List<GenerationEvent>> generateOne() {
      final coordinator = ImageGenerationCoordinator(
        apiService: apiService,
        delay: (duration) async => delays.add(duration),
      );
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 1,
        prepareBatch: (_, params) async => params,
      );
      return coordinator.execute(command, coordinator.start(command)).toList();
    }

    test(
      'five failed retries stop the remaining batch and retain completed images',
      () async {
        final image = Uint8List.fromList([7]);
        streamReplies = (call) => call == 1
            ? [ImageStreamChunk.complete(image)]
            : [ImageStreamChunk.error('API_ERROR_500|down')];
        final coordinator = ImageGenerationCoordinator(apiService: apiService);
        final command = GenerationCommand(
          runId: 1,
          params: const ImageParams(prompt: 'test'),
          batchCount: 4,
          batchSize: 1,
          prepareBatch: (_, params) async => params,
        );
        final events = await coordinator
            .execute(command, coordinator.start(command))
            .toList();
        expect(streamCalls, 7);
        expect(
          events.whereType<GenerationRetrying>().map((event) => event.attempt),
          [1, 2, 3, 4, 5],
        );
        expect(
          events.whereType<GenerationRequestCompleted>().single.images.single,
          same(image),
        );
        expect(
          events.whereType<GenerationRequestFailed>().single.isTerminal,
          isTrue,
        );
        expect(events.last, isA<GenerationFailed>());
        expect(events.whereType<GenerationCompleted>(), isEmpty);
        expect(
          events.whereType<GenerationRequestStarted>().map(
            (event) => event.startImage,
          ),
          [1, 2],
        );
      },
    );

    test('a single-image stream failure is retried five times', () async {
      streamReplies = (_) => [ImageStreamChunk.error('API_ERROR_500|down')];

      final events = await generateOne();

      expect(events.last, isA<GenerationFailed>());
      expect(
        (events.last as GenerationFailed).error.toString(),
        contains('down'),
      );
      expect(streamCalls, 6);
      expect(delays, isEmpty, reason: 'failed requests retry at once');
      final retries = events.whereType<GenerationRetrying>().toList();
      expect(retries.map((event) => event.attempt), [1, 2, 3, 4, 5]);
      for (final retry in retries) {
        expect(retry.maxRetries, ImageGenerationCoordinator.defaultMaxRetries);
        expect(retry.startImage, 1);
        expect(retry.requestSize, 1);
        expect(retry.totalImages, 1);
        expect(retry.error.toString(), contains('down'));
      }
      // Every retry is announced before the request that follows it.
      expect(events.indexOf(retries.last), lessThan(events.length - 2));
    });

    test('a later attempt that succeeds completes the image', () async {
      final image = Uint8List.fromList([7]);
      streamReplies = (call) => call < 3
          ? [ImageStreamChunk.error('API_ERROR_NETWORK|connection reset')]
          : [ImageStreamChunk.complete(image)];

      final events = await generateOne();

      expect(events.last, isA<GenerationCompleted>());
      expect(
        events.whereType<GenerationRequestCompleted>().single.images.single,
        same(image),
      );
      expect(streamCalls, 3);
      expect(delays, isEmpty);
      expect(
        events.whereType<GenerationRetrying>().map((event) => event.attempt),
        [1, 2],
      );
    });

    test('stream and non-stream attempts share the five retries', () async {
      streamReplies = (call) => [
        ImageStreamChunk.error(
          call < 3 ? 'API_ERROR_500|down' : 'Streaming is not allowed',
        ),
      ];
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenThrow(StateError('fallback down'));

      final events = await generateOne();

      expect(events.last, isA<GenerationFailed>());
      expect(
        events.whereType<GenerationRetrying>().map((event) => event.attempt),
        [1, 2, 3, 4, 5],
      );
      expect(streamCalls, 3);
      verify(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(4);
    });

    test('errors that would fail again are not retried', () async {
      for (final error in [
        'API_ERROR_400|invalid size',
        'API_ERROR_401|Unauthorized',
        'API_ERROR_402|Payment required',
      ]) {
        streamCalls = 0;
        delays.clear();
        streamReplies = (_) => [ImageStreamChunk.error(error)];

        final events = await generateOne();

        expect(events.last, isA<GenerationFailed>(), reason: error);
        expect(streamCalls, 1, reason: error);
        expect(delays, isEmpty, reason: error);
        expect(events.whereType<GenerationRetrying>(), isEmpty, reason: error);
      }
    });

    test('a rejected non-stream request is not retried', () async {
      streamReplies = (_) => [
        ImageStreamChunk.error('Streaming is not allowed'),
      ];
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/generate-image'),
          response: Response<void>(
            requestOptions: RequestOptions(path: '/generate-image'),
            statusCode: 402,
          ),
        ),
      );

      final events = await generateOne();

      expect(events.last, isA<GenerationFailed>());
      expect(delays, isEmpty);
      verify(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(1);
    });

    test('429 concurrency waits do not use up the retries', () async {
      final image = Uint8List.fromList([8]);
      streamReplies = (call) => switch (call) {
        1 || 2 => [ImageStreamChunk.error('API_ERROR_429|busy')],
        <= 7 => [ImageStreamChunk.error('API_ERROR_503|unavailable')],
        _ => [ImageStreamChunk.complete(image)],
      };

      final events = await generateOne();

      expect(events.last, isA<GenerationCompleted>());
      expect(streamCalls, 8);
      expect(delays, const [Duration(seconds: 3), Duration(seconds: 3)]);
      expect(
        events.whereType<GenerationRetrying>().map((event) => event.attempt),
        [1, 2, 3, 4, 5],
      );
    });

    test('empty inpaint masks fail without fallback retries', () async {
      final apiService = _MockNAIImageGenerationApiService();
      final delays = <Duration>[];
      when(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenThrow(const EmptyInpaintMaskException());

      final coordinator = ImageGenerationCoordinator(
        apiService: apiService,
        delay: (duration) async => delays.add(duration),
      );
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 1,
        prepareBatch: (_, params) async => params,
        streamPreviewEnabled: false,
      );
      final handle = coordinator.start(command);

      final events = await coordinator.execute(command, handle).toList();

      expect(events.last, isA<GenerationFailed>());
      expect(
        (events.last as GenerationFailed).error,
        isA<EmptyInpaintMaskException>(),
      );
      expect(delays, isEmpty);
      verify(
        () => apiService.generateImage(
          any(),
          onProgress: any(named: 'onProgress'),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(1);
    });

    test('empty inpaint mask stream errors skip multi-image retries', () async {
      final apiService = _MockNAIImageGenerationApiService();
      final delays = <Duration>[];
      const emptyMask = EmptyInpaintMaskException();
      when(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).thenAnswer(
        (_) => Stream.value(ImageStreamChunk.error(emptyMask.toString())),
      );

      final coordinator = ImageGenerationCoordinator(
        apiService: apiService,
        delay: (duration) async => delays.add(duration),
      );
      final command = GenerationCommand(
        runId: 1,
        params: const ImageParams(prompt: 'test'),
        batchCount: 1,
        batchSize: 2,
        prepareBatch: (_, params) async => params,
      );
      final handle = coordinator.start(command);

      final events = await coordinator.execute(command, handle).toList();

      final failed = events.last as GenerationFailed;
      expect(EmptyInpaintMaskException.matches(failed.error), isTrue);
      expect(delays, isEmpty);
      verify(
        () => apiService.generateImageStream(
          any(),
          focusedInpaintEnabled: any(named: 'focusedInpaintEnabled'),
          minimumContextMegaPixels: any(named: 'minimumContextMegaPixels'),
          focusedSelectionRect: any(named: 'focusedSelectionRect'),
        ),
      ).called(1);
    });
  });
}
