import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/constants/model_capabilities.dart';
import '../../core/services/android_foreground_task_service.dart';
import '../../core/services/anlas_calculator.dart';
import '../../core/services/character_conversion_service.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/character_center_resolver.dart';
import '../../core/utils/image_save_utils.dart';
import '../../core/utils/image_share_sanitizer.dart';
import '../../core/utils/nai_prompt_formatter.dart';
import '../../core/utils/nai_resolution_adapter.dart';
import '../../core/utils/prompt_preset_resolution.dart';
import '../../data/datasources/remote/nai_image_generation_api_service.dart';
import '../../data/models/character/character_prompt.dart' as ui_character;
import '../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../data/models/fixed_tag/fixed_tag_usage_snapshot.dart';
import '../../data/models/gallery/character_panel_snapshot.dart';
import '../../data/models/gallery/nai_image_metadata.dart';
import '../../data/models/gallery/prompt_group_snapshot.dart';
import '../../data/models/image/image_params.dart';
import '../../data/models/image/image_stream_chunk.dart';
import 'alias_resolver_service.dart';
import '../../data/services/prompt_group/character_section_store.dart';
import '../../data/services/prompt_group/prompt_group_record_store.dart';
import '../services/generation_history_storage_service.dart';
import '../../data/services/auth_provider.dart';
import 'dlss_provider.dart';
import 'character_prompt_provider.dart';
import 'fixed_tag_usage_provider.dart';
import 'fixed_tags_provider.dart';
import 'generation/generated_image_file_cache.dart';
import 'generation/generated_image_save_queue.dart';
import 'generation/generation_command.dart';
import 'generation/generation_cooldown_provider.dart';
import 'generation/generation_models.dart';
import 'generation/generation_params_notifier.dart';
import 'generation/generation_request_preparation_service.dart';
import 'generation/generation_result_lifecycle_service.dart';
import 'generation/generation_retry_wait_provider.dart';
import 'generation/generation_settings_notifiers.dart';
import 'generation/image_generation_coordinator.dart';
import 'generation/image_workflow_controller.dart';
import 'generation/pending_failed_snapshots.dart';
import 'generation/stream_preview_snapshot.dart';
import 'generation/stream_snapshot_composition.dart';
import 'image_save_settings_provider.dart';
import 'prompt_config_provider.dart';
import 'prompt_group_state_provider.dart';
import 'quality_preset_provider.dart';
import 'queue_execution_provider.dart';
import 'subscription_provider.dart';
import 'system_album_provider.dart';
import 'uc_preset_provider.dart';

export 'generation/generation_models.dart';
export 'generation/generation_cooldown_provider.dart';
export 'generation/generation_retry_wait_provider.dart';
export 'generation/generation_params_notifier.dart';
export 'generation/generation_auxiliary_notifiers.dart';
export 'generation/generation_settings_notifiers.dart';
export 'generation/reference_panel_notifier.dart';
export 'generation/generation_command.dart';
export 'generation/image_generation_coordinator.dart';
export 'generation/generation_request_preparation_service.dart';
export 'generation/generation_result_lifecycle_service.dart';
export 'generation/image_generation_service.dart';
export 'generation/batch_generation_notifier.dart';
export 'generation/stream_generation_notifier.dart';

part 'image_generation_provider.g.dart';

@Riverpod(keepAlive: true)
class ImageGenerationNotifier extends _$ImageGenerationNotifier {
  /// History images whose files are read ahead after a restore.
  static const int _historyPrefetchCount = 24;

  Future<void>? _historyRestoreInFlight;
  bool _hasRestoredHistory = false;
  Completer<void>? _generationInvocationSettled;
  int _invocationCounter = 0;
  int _activeInvocationId = 0;
  int _runCounter = 0;
  int _activeRunId = 0;
  GenerationRunHandle? _activeRun;
  ImageGenerationCoordinator? _coordinator;
  final Map<String, String?> _persistedHistoryFilePaths = <String, String?>{};

  // 清空历史或超出上限只移出记录、保留文件；只有用户删过的结果，晚到的保存要连文件一起清掉。
  final Set<String> _deletedImageIds = <String>{};
  final GeneratedImageSaveQueue _saveQueue = GeneratedImageSaveQueue();
  final StreamPreviewSnapshotStore _streamPreviews =
      StreamPreviewSnapshotStore();
  final Set<String> _failedSnapshotKeys = {};
  final PendingFailedSnapshots _pendingFailedSnapshots =
      PendingFailedSnapshots();
  ImageComparisonSource? _activeComparisonSource;
  FixedTagUsageSnapshot? _activeFixedTagUsageSnapshot;
  PromptGroupSnapshot? _activePromptGroupSnapshot;
  bool _isDisposed = false;
  int _lifecycleEpoch = 0;

  @override
  ImageGenerationState build() {
    ref.onDispose(() {
      _isDisposed = true;
      _lifecycleEpoch++;
      _activeComparisonSource = null;
      _activePromptGroupSnapshot = null;
      _streamPreviews.clear();
      _pendingFailedSnapshots.discardAll();
      final invocationSettled = _generationInvocationSettled;
      _generationInvocationSettled = null;
      if (invocationSettled != null && !invocationSettled.isCompleted) {
        invocationSettled.complete();
      }
      final coordinator = _coordinator;
      final handle = _activeRun;
      if (coordinator != null && handle != null) coordinator.cancel(handle);
    });
    return const ImageGenerationState();
  }

  bool _isCurrentLifecycle(int epoch) =>
      !_isDisposed && epoch == _lifecycleEpoch;

  /// copyWith 省略 errorMessage 等于清空，切换提交标志时必须原样带回。
  void _setSubmitting(bool value) {
    if (state.isSubmitting == value) return;
    state = state.copyWith(
      isSubmitting: value,
      errorMessage: state.errorMessage,
    );
  }

  GenerationResultLifecycleService _lifecycle() {
    return GenerationResultLifecycleService(
      GenerationResultLifecycleDependencies(
        historyStorage: ref.read(generationHistoryStorageServiceProvider),
        systemAlbum: ref.read(systemAlbumProvider),
      ),
    );
  }

  ImageComparisonSource? _comparisonSourceFor(Uint8List bytes) {
    return ImageComparisonSource.fromBytes(
      bytes,
      reuseCandidates: _retainedComparisonSources(),
    );
  }

  /// Reuses only sources already owned by live results; there is deliberately
  /// no separate cache that could outlive history eviction or display cleanup.
  Iterable<ImageComparisonSource> _retainedComparisonSources() sync* {
    final seen = <ImageComparisonSource>{};
    final active = _activeComparisonSource;
    if (active != null && seen.add(active)) yield active;

    for (final images in <List<GeneratedImage>>[
      state.currentImages,
      state.history,
      state.displayImages,
    ]) {
      for (final image in images) {
        final source = image.comparisonSource;
        if (source != null && seen.add(source)) yield source;
      }
    }
  }

  Future<void> ensureGenerationHistoryRestored() {
    if (_isDisposed || _hasRestoredHistory) return Future<void>.value();
    final current = _historyRestoreInFlight;
    if (current != null) return current;
    final epoch = _lifecycleEpoch;
    final lifecycle = _lifecycle();
    late final Future<void> restore;
    restore = _restoreGenerationHistory(lifecycle, epoch).whenComplete(() {
      if (_isCurrentLifecycle(epoch) &&
          identical(_historyRestoreInFlight, restore)) {
        _historyRestoreInFlight = null;
      }
    });
    _historyRestoreInFlight = restore;
    return restore;
  }

  Future<void> _restoreGenerationHistory(
    GenerationResultLifecycleService lifecycle,
    int epoch,
  ) async {
    try {
      final restored = await lifecycle.loadHistory();
      if (!_isCurrentLifecycle(epoch)) return;
      _hasRestoredHistory = true;
      if (restored.isEmpty) return;
      _pendingFailedSnapshots.placeBelowAll(restored.map((image) => image.id));
      final merged = lifecycle.mergeHistory(state.history, restored);
      final restorePreview =
          !state.isGenerating &&
          state.displayImages.isEmpty &&
          merged.isNotEmpty;
      _persistedHistoryFilePaths
        ..clear()
        ..addEntries(
          restored.map((image) => MapEntry(image.id, image.filePath)),
        );
      state = state.copyWith(
        status: state.status == GenerationStatus.idle
            ? GenerationStatus.completed
            : state.status,
        history: merged,
        displayImages: restorePreview ? [merged.first] : state.displayImages,
        displayWidth: restorePreview ? merged.first.width : state.displayWidth,
        displayHeight: restorePreview
            ? merged.first.height
            : state.displayHeight,
      );
      _retainHistoryCaches();
      // The first screen of history reads its files ahead of being shown.
      unawaited(
        GeneratedImageFileCache.prefetch([
          for (final image in merged.take(_historyPrefetchCount))
            if (image.storedPath case final path?) path,
        ]),
      );
    } catch (error, stackTrace) {
      AppLogger.e('Failed to restore generation history', error, stackTrace);
    }
  }

  /// 等仍在合成的失败快照落地后，把历史写入存储。
  Future<void> flushGenerationHistory() async {
    if (_isDisposed) return;
    final lifecycle = _lifecycle();
    await _pendingFailedSnapshots.settled();
    await lifecycle.flushHistory();
  }

  void _retainHistoryCaches() {
    if (_isDisposed) return;
    final retainedIds = <String>{
      for (final image in state.currentImages) image.id,
      for (final image in state.history) image.id,
    };
    unawaited(
      ShareImagePreparationService.instance.retainHistoryImageIds(retainedIds),
    );
    final changed = state.history
        .where(
          (image) =>
              !_persistedHistoryFilePaths.containsKey(image.id) ||
              _persistedHistoryFilePaths[image.id] != image.filePath,
        )
        .toList();
    final historyIds = state.history.map((image) => image.id).toSet();
    final epoch = _lifecycleEpoch;
    final lifecycle = _lifecycle();
    unawaited(
      lifecycle
          .persistHistory(
            changedImages: changed,
            order: state.history.map((image) => image.id).toList(),
          )
          .then((stored) {
            if (!_isCurrentLifecycle(epoch)) return;
            _persistedHistoryFilePaths
              ..removeWhere((id, _) => !historyIds.contains(id))
              ..addEntries(
                changed.map((image) => MapEntry(image.id, image.filePath)),
              );
            _readHistoryFromFiles(stored);
          })
          .catchError((Object _) {}),
    );
  }

  /// Lets persisted history images read their PNG from [stored] files, so a
  /// long history does not keep every image in memory. The bytes already in
  /// memory seed the file cache, so nothing is read back right away.
  void _readHistoryFromFiles(Map<String, String> stored) {
    if (_isDisposed || stored.isEmpty) return;
    var changed = false;
    final history = <GeneratedImage>[];
    for (final image in state.history) {
      final path = stored[image.id];
      if (path == null || image.isStored) {
        history.add(image);
        continue;
      }
      GeneratedImageFileCache.remember(path, image.bytes);
      history.add(image.withStoredFile(path));
      changed = true;
    }
    if (changed) state = state.copyWith(history: history);
  }

  Future<void> waitUntilGenerationInvocationSettled() =>
      _generationInvocationSettled?.future ?? Future<void>.value();

  /// [bypassRandomPrompt]：智能体、MCP 等外部提交方显式给出的提示词不被随机模式替换。
  Future<void> generate(
    ImageParams params, {
    int? batchSizeOverride,
    bool preserveCharacterSnapshot = false,
    GenerationFocusedSnapshot? focusedOverride,
    bool bypassRandomPrompt = false,
  }) async {
    if (_isDisposed || state.isBusy) {
      return;
    }
    _setSubmitting(true);
    final invocationSettled = Completer<void>();
    _generationInvocationSettled = invocationSettled;
    final epoch = _lifecycleEpoch;
    final lifecycle = _lifecycle();
    final subscription = ref.exists(subscriptionNotifierProvider)
        ? ref.read(subscriptionNotifierProvider.notifier)
        : null;
    final invocationId = ++_invocationCounter;
    _activeInvocationId = invocationId;
    Future<void> Function()? releaseForeground;

    try {
      if (!requireAuthenticatedAction(ref, AuthPromptReason.imageGeneration)) {
        return;
      }
      final liveParams = ref.read(generationParamsNotifierProvider);
      final useRestoredLiveParams = identical(params, liveParams);
      if (ref.read(generationSessionPersistenceEnabledProvider)) {
        await Future.wait<void>([
          ensureGenerationHistoryRestored(),
          ref
              .read(generationParamsNotifierProvider.notifier)
              .restoreGenerationState(),
        ]);
        if (!_isCurrentLifecycle(epoch) ||
            _activeInvocationId != invocationId) {
          return;
        }
      }
      final effectiveParams = useRestoredLiveParams
          ? ref.read(generationParamsNotifierProvider)
          : params;
      final promptGroupCandidate = ref.read(currentPromptGroupSnapshotProvider);
      final promptGroupSnapshot =
          promptGroupCandidate?.positivePrompt == effectiveParams.prompt &&
              promptGroupCandidate?.negativePrompt ==
                  effectiveParams.negativePrompt
          ? promptGroupCandidate
          : null;
      final issue = NaiResolutionAdapter.validateGenerationResolution(
        effectiveParams.width,
        effectiveParams.height,
      );
      if (issue != null) {
        state = state.copyWith(
          status: GenerationStatus.error,
          errorMessage: issue.errorCode,
          progress: 0,
        );
        return;
      }
      if (!ref.read(generationCooldownProvider.notifier).tryStartGeneration()) {
        return;
      }

      try {
        releaseForeground = await ref
            .read(androidForegroundTaskServiceProvider)
            .acquire();
      } catch (error, stackTrace) {
        AppLogger.e(
          'Unable to start Android generation foreground service',
          error,
          stackTrace,
        );
      }
      if (!_isCurrentLifecycle(epoch) || _activeInvocationId != invocationId) {
        return;
      }

      // A request that brings its own characters (agent, queue snapshot)
      // still sends the panel's when their prompts match; only then do the
      // panel's fixed-tag claims and record apply to it.
      final panelSent =
          !preserveCharacterSnapshot || _panelSends(effectiveParams);
      final preparation = _preparationService(
        preserveCharacterSnapshot: preserveCharacterSnapshot,
        panelSent: panelSent,
        focusedOverride: focusedOverride,
        bypassRandomPrompt: bypassRandomPrompt,
      );
      late final GenerationPreparationResult prepared;
      try {
        prepared = await preparation.prepareInitial(effectiveParams);
      } on UnsupportedRandomPromptModelException catch (error, stackTrace) {
        AppLogger.e(
          'Generation preparation rejected an unsupported random model',
          error,
          stackTrace,
        );
        if (_isCurrentLifecycle(epoch) && _activeInvocationId == invocationId) {
          state = state.copyWith(
            status: GenerationStatus.error,
            errorMessage: error.encodedMessage,
            progress: 0,
          );
        }
        return;
      }
      if (!_isCurrentLifecycle(epoch) || _activeInvocationId != invocationId) {
        return;
      }
      final runId = ++_runCounter;
      _activeRunId = runId;
      _activeFixedTagUsageSnapshot = prepared.fixedTagUsageSnapshot;
      _activePromptGroupSnapshot = PromptGroupSnapshot.withCharacters(
        promptGroupSnapshot,
        panelSent ? _characterPanelSnapshot(prepared.params) : null,
      );
      _streamPreviews.clear();
      _failedSnapshotKeys.clear();
      final dlss = ref.read(dlssProvider);
      final coordinator = ImageGenerationCoordinator(
        apiService: ref.read(naiImageGenerationApiServiceProvider),
        delay: ref.read(generationRetryWaitProvider),
        postprocess: dlss.automaticSnapshot(),
        onPostprocessError: dlss.reportEnhancementError,
      );
      _coordinator = coordinator;
      final command = GenerationCommand(
        runId: runId,
        params: prepared.params,
        batchCount: prepared.params.nSamples,
        batchSize: batchSizeOverride ?? ref.read(imagesPerRequestProvider),
        prepareBatch: (batch, current) async {
          if (batch == 0) return current;
          final next = await preparation.prepareSubsequentBatch(current);
          return next;
        },
        focusedInpaintEnabled: prepared.focusedSnapshot.enabled,
        minimumContextMegaPixels:
            prepared.focusedSnapshot.minimumContextMegaPixels,
        focusedSelectionRect: prepared.focusedSnapshot.selectionRect,
        focusedContextCrop: prepared.focusedSnapshot.contextCrop,
        streamPreviewEnabled: ref.read(generationStreamPreviewSettingsProvider),
      );
      final handle = coordinator.start(command);
      _activeRun = handle;
      await for (final event in coordinator.execute(command, handle)) {
        await _reduce(event, epoch);
      }
    } finally {
      // 归属判断不可省：被取消后新一次提交已经接管标志，这里不能替它复位。
      if (_isCurrentLifecycle(epoch) && _activeInvocationId == invocationId) {
        _activeInvocationId = 0;
        _setSubmitting(false);
        _activeComparisonSource = null;
        _activeFixedTagUsageSnapshot = null;
        _activePromptGroupSnapshot = null;
      }
      if (!invocationSettled.isCompleted) {
        invocationSettled.complete();
      }
      if (identical(_generationInvocationSettled, invocationSettled)) {
        _generationInvocationSettled = null;
      }
      if (releaseForeground != null) {
        try {
          await releaseForeground();
        } catch (error, stackTrace) {
          AppLogger.e(
            'Unable to stop Android generation foreground service',
            error,
            stackTrace,
          );
        }
      }
      try {
        await lifecycle.flushHistory();
      } catch (error, stackTrace) {
        AppLogger.e(
          'Failed to flush generation history after generation',
          error,
          stackTrace,
        );
      }
      if (_isCurrentLifecycle(epoch)) {
        subscription?.schedulePostBillingRefresh();
      }
    }
  }

  GenerationRequestPreparationService _preparationService({
    bool preserveCharacterSnapshot = false,
    bool panelSent = true,
    GenerationFocusedSnapshot? focusedOverride,
    bool bypassRandomPrompt = false,
  }) {
    var queueExecuting = false;
    try {
      final queue = ref.read(queueExecutionNotifierProvider);
      queueExecuting = queue.isRunning || queue.isReady;
    } catch (_) {
      queueExecuting = false;
    }
    final aliases = ref.read(aliasResolverServiceProvider.notifier);
    final fixedTags = ref.read(fixedTagsNotifierProvider);
    // Fixed tags the included characters carry stay out of the main prompt.
    final claimed = panelSent
        ? ref.read(characterPromptNotifierProvider.notifier).claimedFixedTags()
        : const <String>{};
    final mainFixedTags = claimed.isEmpty
        ? fixedTags.entries
        : [
            for (final entry in fixedTags.entries)
              if (!claimed.contains(entry.id)) entry,
          ];
    return GenerationRequestPreparationService(
      GenerationPreparationDependencies(
        prompt: GenerationPromptPreparation(
          randomModeEnabled:
              !bypassRandomPrompt && ref.read(randomPromptModeProvider),
          queueExecuting: queueExecuting,
          generateAndApplyRandomPrompt: (model) =>
              generateAndApplyRandomPrompt(model: model),
          resolveAliases: aliases.resolveAliases,
          applyFixedPositiveTags: mainFixedTags.applyToPrompt,
          applyFixedNegativeTags: mainFixedTags.applyToNegativePrompt,
          resolvePresets: _resolvePromptPresets,
          fixedTagUsageSnapshot: FixedTagUsageSnapshot.capture(
            fixedTags.entries,
            claimedIds: claimed,
          ),
        ),
        characters: GenerationCharacterPreparation(
          read: (_) {
            ref.read(characterPromptNotifierProvider.notifier).syncFixedTags();
            final config = ref.read(characterPromptNotifierProvider);
            final characters = _convertCharactersToApiFormat(config);
            return CharacterPreparationSnapshot(
              characters: characters,
              useCoords: characters.isNotEmpty && !config.globalAiChoice,
            );
          },
        ),
        focused: GenerationFocusedPreparation(
          // 只有生成页会把聚焦状态存在 workflow 里；Agent 等其他提交方必须显式
          // 传入，否则会继承上一张图残留的聚焦选区。
          read: () {
            if (focusedOverride != null) return focusedOverride;
            final workflow = ref.read(imageWorkflowControllerProvider);
            return GenerationFocusedSnapshot(
              enabled: workflow.focusedInpaintEnabled,
              minimumContextMegaPixels: workflow.minimumContextMegaPixels,
              selectionRect: workflow.focusedSelectionRect,
              contextCrop: workflow.focusedContextCrop,
            );
          },
        ),
        vibes: GenerationVibePreparation(prepare: _prepareVibesForGeneration),
      ),
      preserveCharacterSnapshot: preserveCharacterSnapshot,
    );
  }

  Future<void> _reduce(GenerationEvent event, int epoch) async {
    if (!_isCurrentLifecycle(epoch) || event.runId != _activeRunId) return;
    switch (event) {
      case GenerationStarted(:final params, :final totalImages):
        final sourceImage = params.sourceImage;
        // Generate may still carry canvas data, but only image transformations
        // have a source that represents the visual input to the result.
        _activeComparisonSource =
            sourceImage != null &&
                params.action != ImageGenerationAction.generate
            ? _comparisonSourceFor(sourceImage)
            : null;
        state = state.copyWith(
          currentImages: [],
          status: GenerationStatus.generating,
          progress: 0,
          currentImage: totalImages > 0 ? 1 : 0,
          totalImages: totalImages,
          batchWidth: params.width,
          batchHeight: params.height,
          completionPreviews: const {},
          clearStreamPreview: true,
          retryAttempt: 0,
        );
      case GenerationRequestStarted(
        :final params,
        :final startImage,
        :final requestSize,
        :final totalImages,
      ):
        state = state.copyWith(
          currentImage: startImage,
          totalImages: totalImages,
          progress: (startImage - 1) / totalImages,
          batchWidth: params.width,
          batchHeight: params.height,
          streamPreviewSlots: [
            for (var i = 0; i < requestSize; i++)
              StreamPreviewSlot(
                imageNumber: startImage + i,
                totalImages: totalImages,
                progress: 0,
              ),
          ],
          clearStreamPreview: true,
          retryAttempt: 0,
        );
      case GenerationImageStarted(:final imageNumber, :final totalImages):
        state = state.copyWith(
          currentImage: imageNumber,
          progress: (imageNumber - 1) / totalImages,
          retryAttempt: 0,
        );
      case GenerationRetrying(
        :final startImage,
        :final requestSize,
        :final totalImages,
        :final attempt,
        :final maxRetries,
      ):
        // The retry starts over, so the failed attempt's preview goes away.
        var slots = state.streamPreviewSlots;
        for (var i = 0; i < requestSize; i++) {
          slots = _replacePreviewSlot(
            slots,
            StreamPreviewSlot(
              imageNumber: startImage + i,
              totalImages: totalImages,
              progress: 0,
              retryAttempt: attempt,
              maxRetries: maxRetries,
            ),
          );
        }
        state = state.copyWith(
          currentImage: startImage,
          progress: (startImage - 1) / totalImages,
          streamPreviewSlots: slots,
          clearStreamPreview: true,
          retryAttempt: attempt,
          maxRetries: maxRetries,
        );
      case GenerationPreviewReceived(
        :final params,
        :final imageNumber,
        :final totalImages,
        :final progress,
        :final bytes,
        :final focusedPreviewPlacement,
      ):
        _rememberPreview(
          event.runId,
          imageNumber,
          bytes,
          params,
          focusedPreviewPlacement,
        );
        final retried = state.streamPreviewSlots
            .where((slot) => slot.imageNumber == imageNumber)
            .firstOrNull;
        final slot = StreamPreviewSlot(
          imageNumber: imageNumber,
          totalImages: totalImages,
          progress: progress,
          previewBytes: bytes,
          focusedPreviewPlacement: focusedPreviewPlacement,
          retryAttempt: retried?.retryAttempt ?? 0,
          maxRetries: retried?.maxRetries ?? 0,
        );
        state = state.copyWith(
          currentImage: imageNumber,
          progress: ((imageNumber - 1) + progress) / totalImages,
          streamPreview: bytes,
          focusedPreviewPlacement: focusedPreviewPlacement,
          clearFocusedPreviewPlacement: focusedPreviewPlacement == null,
          streamPreviewSlots: _replacePreviewSlot(
            state.streamPreviewSlots,
            slot,
          ),
        );
      case GenerationImageFinalizing(:final imageNumber, :final totalImages):
        state = state.copyWith(
          currentImage: imageNumber,
          progress: imageNumber / totalImages,
          streamPreviewSlots: _replacePreviewSlot(
            state.streamPreviewSlots,
            _finalizedPreviewSlot(imageNumber, totalImages),
          ),
        );
      case GenerationPostprocessChanged(
        :final imageNumber,
        :final totalImages,
        :final phase,
      ):
        state = state.copyWith(
          streamPreviewSlots: _replacePreviewSlot(
            state.streamPreviewSlots,
            _finalizedPreviewSlot(
              imageNumber,
              totalImages,
            ).copyWith(postprocessPhase: phase),
          ),
        );
      case GenerationRequestCompleted(
        :final params,
        :final startImage,
        :final totalImages,
        :final images,
        :final vibeEncodings,
        :final postprocessErrors,
      ):
        final generated = <GeneratedImage>[];
        for (final entry in images.indexed) {
          final bytes = entry.$2;
          final outputSize =
              NaiResolutionAdapter.readImageSize(bytes) ??
              (params.width, params.height);
          generated.add(
            GeneratedImage.create(
              bytes,
              postprocessError: postprocessErrors[entry.$1],
              width: params.width,
              height: params.height,
              comparisonSource: _activeComparisonSource,
              fixedTagUsageSnapshot: _activeFixedTagUsageSnapshot,
              metadata: _metadataFromParams(
                params,
                outputWidth: outputSize.$1,
                outputHeight: outputSize.$2,
                fixedTagUsageSnapshot: _activeFixedTagUsageSnapshot,
              ),
            ),
          );
        }
        final current = [...state.currentImages, ...generated];
        final history = [
          ...generated,
          ...state.history,
        ].take(GenerationResultLifecycleService.historyLimit).toList();
        state = state.copyWith(
          currentImages: current,
          history: history,
          progress: (startImage - 1 + images.length) / totalImages,
          completionPreviews: _captureCompletionPreviews(
            generated: generated,
            startImage: startImage,
            currentImages: current,
            history: history,
          ),
          clearStreamPreview: true,
          retryAttempt: 0,
        );
        for (var i = 0; i < max(images.length, params.nSamples); i++) {
          _streamPreviews.release(event.runId, startImage + i);
        }
        _saveVibeEncodings(vibeEncodings);
        _retainHistoryCaches();
        _recordPromptGroups(images);
        _recordFixedTagUsage(images.length);
      case GenerationRequestSkipped(:final startImage, :final requestSize):
        _appendFailedSnapshots(event.runId);
        for (var i = 0; i < requestSize; i++) {
          _streamPreviews.release(event.runId, startImage + i);
        }
        state = state.copyWith(clearStreamPreview: true, retryAttempt: 0);
      case GenerationRequestFailed(:final error, :final isTerminal):
        _appendFailedSnapshots(event.runId);
        if (isTerminal) {
          _activeComparisonSource = null;
          state = state.copyWith(
            status: GenerationStatus.error,
            errorMessage: error.toString(),
            progress: 0,
            currentImage: 0,
            totalImages: 0,
            clearStreamPreview: true,
            retryAttempt: 0,
          );
        } else {
          state = state.copyWith(retryAttempt: 0);
        }
      case GenerationCompleted(:final params):
        final images = List<GeneratedImage>.from(state.currentImages);
        _activeComparisonSource = null;
        _streamPreviews.clear();
        state = state.copyWith(
          status: GenerationStatus.completed,
          displayImages: images,
          displayWidth: images.isEmpty ? params.width : images.first.width,
          displayHeight: images.isEmpty ? params.height : images.first.height,
          progress: 1,
          currentImage: 0,
          totalImages: 0,
          clearStreamPreview: true,
          retryAttempt: 0,
        );
        if (images.isNotEmpty) {
          final settings = ref.read(imageSaveSettingsNotifierProvider);
          if (settings.autoSave) {
            await _saveImages(images, params, epoch: epoch);
            if (!_isCurrentLifecycle(epoch) || event.runId != _activeRunId) {
              return;
            }
          }
        }
      case GenerationCancelled():
        _appendFailedSnapshots(event.runId);
        _streamPreviews.clear();
        _activeComparisonSource = null;
        state = state.copyWith(
          status: GenerationStatus.cancelled,
          progress: 0,
          currentImage: 0,
          totalImages: 0,
          clearStreamPreview: true,
          retryAttempt: 0,
        );
      case GenerationFailed(:final error):
        _appendFailedSnapshots(event.runId);
        _streamPreviews.clear();
        _activeComparisonSource = null;
        state = state.copyWith(
          status: GenerationStatus.error,
          errorMessage: error.toString(),
          progress: 0,
          currentImage: 0,
          totalImages: 0,
          clearStreamPreview: true,
          retryAttempt: 0,
        );
    }
  }

  // 预览帧字节由解码与协调层逐帧新建，不会被复用，直接持有即可。
  void _rememberPreview(
    int runId,
    int imageNumber,
    Uint8List bytes,
    ImageParams params,
    FocusedStreamPreviewPlacement? placement,
  ) {
    _streamPreviews.remember(
      runId: runId,
      imageNumber: imageNumber,
      bytes: bytes,
      params: params,
      placement: placement,
    );
  }

  String _snapshotKey(int runId, int imageNumber) => '$runId:$imageNumber';

  /// 固定词“常用”排序的依据：每张生成的图给随它发送的固定词各记一次。
  void _recordFixedTagUsage(int images) {
    final usage = _activeFixedTagUsageSnapshot;
    if (usage == null || images <= 0) return;
    final ids = usage.entries
        .map((entry) => entry.fixedTagId)
        .whereType<String>();
    try {
      ref.read(fixedTagUsageProvider.notifier).record(ids, images: images);
    } catch (error, stackTrace) {
      AppLogger.e('Failed to record fixed tag usage', error, stackTrace);
    }
  }

  /// 为取消、跳过或失败那一刻各槽位的最后一帧留下只读快照。
  ///
  /// 需要贴回源图的重绘快照交给后台合成，这里只预留它在历史中的位置。
  void _appendFailedSnapshots(int runId) {
    final numbers = state.streamPreviewSlots.isNotEmpty
        ? state.streamPreviewSlots.map((slot) => slot.imageNumber).toList()
        : state.currentImage > 0
        ? [state.currentImage]
        : const <int>[];
    final fixedTagUsage = _activeFixedTagUsageSnapshot;
    final capturedAt = DateTime.now();
    for (final number in numbers.reversed) {
      final key = _snapshotKey(runId, number);
      final preview = _streamPreviews.preview(runId, number);
      if (preview == null || !_failedSnapshotKeys.add(key)) continue;
      _streamPreviews.release(runId, number);
      final frame = StreamPreviewFrame(
        bytes: preview.bytes,
        placement: preview.focusedPreviewPlacement,
      );
      if (streamSnapshotPlacement(frame) == null) {
        final snapshot = _failedSnapshot(
          frame.bytes,
          preview.params,
          fixedTagUsage,
          createdAt: capturedAt,
        );
        _commitHistory([snapshot, ...state.history]);
        continue;
      }
      final id = _pendingFailedSnapshots.reserve(state.history);
      _pendingFailedSnapshots.track(
        _landFailedSnapshot(
          id,
          frame,
          compose: ref.read(streamSnapshotComposerProvider),
          params: preview.params,
          fixedTagUsage: fixedTagUsage,
          capturedAt: capturedAt,
          epoch: _lifecycleEpoch,
        ),
      );
    }
    _retainHistoryCaches();
  }

  Future<void> _landFailedSnapshot(
    String id,
    StreamPreviewFrame frame, {
    required StreamSnapshotComposer compose,
    required ImageParams params,
    required FixedTagUsageSnapshot? fixedTagUsage,
    required DateTime capturedAt,
    required int epoch,
  }) async {
    Uint8List bytes;
    try {
      bytes = await compose(frame);
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to compose stream snapshot; keeping the raw preview',
        error,
        stackTrace,
      );
      bytes = frame.bytes;
    }
    if (!_isCurrentLifecycle(epoch)) return;
    final floor = _pendingFailedSnapshots.take(id);
    if (floor == null) return;
    final snapshot = _failedSnapshot(
      bytes,
      params,
      fixedTagUsage,
      id: id,
      createdAt: capturedAt,
    );
    _commitHistory(
      PendingFailedSnapshots.insert(state.history, snapshot, floor),
    );
    _retainHistoryCaches();
  }

  GeneratedImage _failedSnapshot(
    Uint8List bytes,
    ImageParams params,
    FixedTagUsageSnapshot? fixedTagUsage, {
    required DateTime createdAt,
    String? id,
  }) {
    final size =
        NaiResolutionAdapter.readImageSize(bytes) ??
        (params.width, params.height);
    return GeneratedImage.create(
      bytes,
      id: id,
      createdAt: createdAt,
      width: size.$1,
      height: size.$2,
      kind: GeneratedImageKind.failedStreamSnapshot,
      fixedTagUsageSnapshot: fixedTagUsage,
      metadata: _metadataFromParams(
        params,
        outputWidth: size.$1,
        outputHeight: size.$2,
        fixedTagUsageSnapshot: fixedTagUsage,
      ),
    );
  }

  /// 快照可能在失败状态写入之后才落地，copyWith 省略 errorMessage 会把错误清掉。
  void _commitHistory(List<GeneratedImage> history) {
    state = state.copyWith(
      history: history
          .take(GenerationResultLifecycleService.historyLimit)
          .toList(),
      errorMessage: state.errorMessage,
    );
  }

  StreamPreviewSlot _finalizedPreviewSlot(int imageNumber, int totalImages) {
    for (final slot in state.streamPreviewSlots) {
      if (slot.imageNumber == imageNumber) return slot.copyWith(progress: 1);
    }
    return StreamPreviewSlot(
      imageNumber: imageNumber,
      totalImages: totalImages,
      progress: 1,
    );
  }

  Map<String, StreamPreviewFrame> _captureCompletionPreviews({
    required List<GeneratedImage> generated,
    required int startImage,
    required List<GeneratedImage> currentImages,
    required List<GeneratedImage> history,
  }) {
    final retainedIds = <String>{
      for (final image in currentImages) image.id,
      for (final image in history) image.id,
    };
    final previews = <String, StreamPreviewFrame>{
      for (final entry in state.completionPreviews.entries)
        if (retainedIds.contains(entry.key)) entry.key: entry.value,
    };
    for (var i = 0; i < generated.length; i++) {
      final frame = _completionFrameFor(startImage + i, generated.length);
      if (frame != null) previews[generated[i].id] = frame;
    }
    return previews;
  }

  /// ImageCache 以字节身份为键，必须交出槽位里的原实例，拷贝会让完成卡片重新解码。
  StreamPreviewFrame? _completionFrameFor(int imageNumber, int generatedCount) {
    for (final slot in state.streamPreviewSlots) {
      if (slot.imageNumber != imageNumber) continue;
      final bytes = slot.previewBytes;
      if (bytes == null || bytes.isEmpty) return null;
      return StreamPreviewFrame(
        bytes: bytes,
        placement: slot.focusedPreviewPlacement,
      );
    }
    if (state.streamPreviewSlots.isNotEmpty || generatedCount != 1) return null;
    final bytes = state.streamPreview;
    if (bytes == null || bytes.isEmpty) return null;
    return StreamPreviewFrame(
      bytes: bytes,
      placement: state.focusedPreviewPlacement,
    );
  }

  List<StreamPreviewSlot> _replacePreviewSlot(
    List<StreamPreviewSlot> slots,
    StreamPreviewSlot replacement,
  ) {
    final found = slots.any(
      (slot) => slot.imageNumber == replacement.imageNumber,
    );
    final result = <StreamPreviewSlot>[
      for (final slot in slots)
        if (slot.imageNumber == replacement.imageNumber) replacement else slot,
      if (!found) replacement,
    ];
    result.sort((a, b) => a.imageNumber.compareTo(b.imageNumber));
    return result;
  }

  void skipCurrentRequest() {
    final coordinator = _coordinator;
    final handle = _activeRun;
    if (coordinator == null || handle == null) {
      cancel();
      return;
    }
    final runId = _activeRunId;
    final skipped = coordinator.skipCurrentRequest(handle);
    _appendFailedSnapshots(runId);
    if (!skipped) return;
    state = state.copyWith(clearStreamPreview: true);
  }

  void cancel() {
    if (_isDisposed) return;
    final processingCoordinator = _coordinator;
    final processingRun = _activeRun;
    if (processingCoordinator != null &&
        processingRun != null &&
        processingCoordinator.isPostprocessing) {
      // Keep this run's ownership until its already-arrived originals are reduced.
      processingCoordinator.cancel(processingRun);
      return;
    }
    final runId = _activeRunId;
    _activeInvocationId = 0;
    _activeComparisonSource = null;
    final coordinator = _coordinator;
    final handle = _activeRun;
    if (coordinator != null && handle != null) coordinator.cancel(handle);
    _appendFailedSnapshots(runId);
    _streamPreviews.clear();
    _activeRunId = ++_runCounter;
    // 图已出完、只剩落盘收尾时点取消，不该把已有结果改标成已取消。
    final settled = state.status == GenerationStatus.completed;
    state = state.copyWith(
      status: settled ? state.status : GenerationStatus.cancelled,
      progress: settled ? state.progress : 0,
      currentImage: 0,
      totalImages: 0,
      clearStreamPreview: true,
      isSubmitting: false,
    );
  }

  /// Registers a result produced outside the normal generation stream.
  ///
  /// [comparisonSourceImage] is supplied by single-source transformations such
  /// as NovelAI upscale and local upscale so their result can be compared.
  /// With [saveToLocal] the result also goes to the system album, and its
  /// location there is returned; null when it was not saved.
  Future<String?> registerExternalImage(
    Uint8List imageBytes, {
    required ImageParams params,
    int? width,
    int? height,
    Uint8List? comparisonSourceImage,
    bool saveToLocal = false,
    bool addToDisplay = false,
    bool replaceCurrentDisplay = false,
    bool embedNaiMetadata = true,
  }) async {
    assert(!addToDisplay || !replaceCurrentDisplay);
    if (_isDisposed) return null;
    final epoch = _lifecycleEpoch;
    final lifecycle = _lifecycle();
    final prepared = await lifecycle.prepareExternalImage(
      imageBytes,
      params: params,
      width: width,
      height: height,
      comparisonSource: comparisonSourceImage == null
          ? null
          : _comparisonSourceFor(comparisonSourceImage),
      embedNaiMetadata: embedNaiMetadata,
    );
    if (!_isCurrentLifecycle(epoch)) return null;
    final image = prepared.image;
    final shouldDisplay = addToDisplay || replaceCurrentDisplay;
    state = state.copyWith(
      currentImages: replaceCurrentDisplay
          ? [image]
          : addToDisplay
          ? [image, ...state.currentImages]
          : state.currentImages,
      history: [
        image,
        ...state.history,
      ].take(GenerationResultLifecycleService.historyLimit).toList(),
      displayImages: replaceCurrentDisplay
          ? [image]
          : addToDisplay
          ? [image, ...state.displayImages]
          : state.displayImages,
      displayWidth: shouldDisplay ? image.width : state.displayWidth,
      displayHeight: shouldDisplay ? image.height : state.displayHeight,
    );
    _retainHistoryCaches();
    if (saveToLocal) {
      final result = await _saveImages([image], prepared.params, epoch: epoch);
      return _deletedImageIds.contains(image.id)
          ? null
          : result.albumLocations.firstOrNull;
    }
    return null;
  }

  /// Runs [save] once no other save of [imageId] is still writing its file.
  Future<T> queueImageSave<T>(String imageId, Future<T> Function() save) =>
      _saveQueue.run([imageId], save);

  GeneratedImage? findImageById(String imageId) => state.findImageById(imageId);

  Future<GenerationSaveResult> _saveImages(
    List<GeneratedImage> images,
    ImageParams params, {
    required int epoch,
  }) => _saveQueue.run([
    for (final image in images) image.id,
  ], () => _writeImages(images, params, epoch: epoch));

  Future<GenerationSaveResult> _writeImages(
    List<GeneratedImage> queuedImages,
    ImageParams params, {
    required int epoch,
  }) async {
    if (!_isCurrentLifecycle(epoch)) {
      return GenerationSaveResult(queuedImages, const []);
    }
    // 排队期间被删除的结果不再存进相册。
    final images = [
      for (final image in queuedImages)
        if (!_deletedImageIds.contains(image.id)) image,
    ];
    final fixedTagUsageSnapshot =
        (images.isEmpty ? null : images.first.fixedTagUsageSnapshot) ??
        FixedTagUsageSnapshot.capture(
          ref.read(fixedTagsNotifierProvider).entries,
        );
    return _lifecycle().saveImages(
      images,
      params,
      snapshot: GenerationSaveSnapshot(
        fixedTagUsageSnapshot: fixedTagUsageSnapshot,
        useCoords: params.useCoords,
      ),
    );
  }

  void _replaceImage(String id, GeneratedImage replacement) {
    state = state.copyWith(
      currentImages: state.currentImages
          .map((image) => image.id == id ? replacement : image)
          .toList(),
      history: state.history
          .map((image) => image.id == id ? replacement : image)
          .toList(),
      displayImages: state.displayImages
          .map((image) => image.id == id ? replacement : image)
          .toList(),
    );
    _retainHistoryCaches();
  }

  void clearCurrent() {
    state = state.copyWith(
      currentImages: [],
      status: GenerationStatus.idle,
      completionPreviews: const {},
    );
    _retainHistoryCaches();
  }

  void clearError() {
    if (state.status == GenerationStatus.error) {
      state = state.copyWith(status: GenerationStatus.idle, errorMessage: null);
    }
  }

  void clearHistory() {
    _pendingFailedSnapshots.discardAll();
    state = state.copyWith(
      currentImages: [],
      history: [],
      completionPreviews: const {},
    );
    _retainHistoryCaches();
  }

  /// 从当前批次、历史与中央预览永久移除这些结果。
  ///
  /// 收藏进图库的文件不受影响：图库只放收藏，取消收藏才会删除它们。
  Future<GeneratedImageRemovalResult> removeImages(
    Iterable<String> imageIds,
  ) async {
    if (_isDisposed) return const GeneratedImageRemovalResult();
    final ids = imageIds.toSet();
    final removed = <String, GeneratedImage>{
      for (final image in [
        ...state.currentImages,
        ...state.history,
        ...state.displayImages,
      ])
        if (ids.contains(image.id)) image.id: image,
    };
    if (removed.isEmpty) return const GeneratedImageRemovalResult();
    _deletedImageIds.addAll(removed.keys);

    bool retained(GeneratedImage image) => !removed.containsKey(image.id);
    final displayImages = state.displayImages.where(retained).toList();
    state = state.copyWith(
      currentImages: state.currentImages.where(retained).toList(),
      history: state.history.where(retained).toList(),
      displayImages: displayImages,
      displayWidth: displayImages.isEmpty ? null : displayImages.first.width,
      displayHeight: displayImages.isEmpty ? null : displayImages.first.height,
      completionPreviews: {
        for (final entry in state.completionPreviews.entries)
          if (!removed.containsKey(entry.key)) entry.key: entry.value,
      },
      errorMessage: state.errorMessage,
    );
    _retainHistoryCaches();
    return GeneratedImageRemovalResult(removedCount: removed.length);
  }

  void updateDisplayImages(List<GeneratedImage> images) {
    state = state.copyWith(displayImages: images);
  }

  /// 收藏写入图库后回写路径。结果已被删除时什么都不做：收藏是用户的选择，
  /// 只有取消收藏才会把图库里的文件删掉。
  void updateImageFilePath(String imageId, String filePath) {
    if (_deletedImageIds.contains(imageId)) return;
    final image = state.findImageById(imageId);
    if (image == null) return;
    _replaceImage(imageId, image.copyWithFilePath(filePath));
  }

  Future<ImageParams> _prepareVibesForGeneration(ImageParams params) async {
    if (!AnlasCalculator.usesVibeReferences(params) ||
        !params.capabilities.supportsEncodedVibeTransfer) {
      return params;
    }
    final encoded = await ref
        .read(generationParamsNotifierProvider.notifier)
        .ensureVibeReferencesEncoded(
          params.vibeReferencesV4,
          model: params.model,
          syncCurrentState: true,
        );
    return identical(encoded, params.vibeReferencesV4)
        ? params
        : params.copyWith(vibeReferencesV4: encoded);
  }

  PromptPresetResolution _resolvePromptPresets(ImageParams params) {
    final quality = ref.read(qualityPresetNotifierProvider);
    final uc = ref.read(ucPresetNotifierProvider);
    return resolvePromptPresetSettings(
      prompt: params.prompt,
      negativePrompt: params.negativePrompt,
      qualityMode: quality.mode,
      qualityContent: ref
          .read(qualityPresetNotifierProvider.notifier)
          .getEffectiveContent(params.model),
      ucPresetType: uc.presetType,
      ucPresetContent: ref
          .read(ucPresetNotifierProvider.notifier)
          .getEffectiveContent(params.model),
      useCustomUcPreset: uc.isCustom,
    );
  }

  List<CharacterPrompt> _convertCharactersToApiFormat(
    ui_character.CharacterPromptConfig config,
  ) {
    return CharacterConversionService(
      aliasResolver: ref
          .read(aliasResolverServiceProvider.notifier)
          .resolveAliases,
    ).convert(config).characters;
  }

  Future<String> generateAndApplyRandomPrompt({
    int? seed,
    String? model,
  }) async {
    if (_isDisposed) return '';
    final epoch = _lifecycleEpoch;
    final params = ref.read(generationParamsNotifierProvider);
    final selectedModel = model ?? params.model;
    final capabilities = ModelCapabilityRegistry.of(selectedModel);
    final result = await ref
        .read(promptConfigNotifierProvider.notifier)
        .generateRandomPrompt(model: selectedModel, seed: seed);
    final formatted = NaiPromptFormatter.format(result.mainPrompt);
    if (!_isCurrentLifecycle(epoch)) return formatted;
    ref.read(generationParamsNotifierProvider.notifier).updatePrompt(formatted);
    if (result.hasCharacters &&
        capabilities.randomPromptProfile.supportsCharacterPrompts) {
      final characters = result.toCharacterPrompts().map((character) {
        return character.copyWith(
          prompt: NaiPromptFormatter.format(character.prompt),
          negativePrompt: character.negativePrompt.isEmpty
              ? character.negativePrompt
              : NaiPromptFormatter.format(character.negativePrompt),
        );
      }).toList();
      ref.read(characterPromptNotifierProvider.notifier).replaceAll(characters);
    } else if (result.noHumans) {
      ref.read(characterPromptNotifierProvider.notifier).clearAll();
    }
    return formatted;
  }

  void _saveVibeEncodings(Map<int, String> encodings) {
    for (final entry in encodings.entries) {
      if (entry.value.isEmpty) continue;
      ref
          .read(generationParamsNotifierProvider.notifier)
          .updateVibeReference(entry.key, vibeEncoding: entry.value);
    }
  }

  NaiImageMetadata _metadataFromParams(
    ImageParams params, {
    required int outputWidth,
    required int outputHeight,
    required FixedTagUsageSnapshot? fixedTagUsageSnapshot,
  }) {
    final effective = params.resolveFixedSettings().copyWith(
      width: outputWidth,
      height: outputHeight,
    );
    final charCaptions = <Map<String, dynamic>>[];
    final charNegCaptions = <Map<String, dynamic>>[];
    for (var index = 0; index < effective.characters.length; index++) {
      final character = effective.characters[index];
      final center = CharacterCenterResolver.resolve(
        character,
        index: index,
        total: effective.characters.length,
        useCoords: effective.useCoords,
      );
      final x = center.x;
      final y = center.y;
      charCaptions.add({
        'char_caption': character.prompt,
        'centers': [
          {'x': x, 'y': y},
        ],
      });
      charNegCaptions.add({
        'char_caption': character.negativePrompt,
        'centers': [
          {'x': x, 'y': y},
        ],
      });
    }
    final comment = ImageSaveUtils.buildCommentJson(
      params: effective,
      actualSeed: effective.seed,
      charCaptions: charCaptions,
      charNegCaptions: charNegCaptions,
      useCoords: effective.useCoords,
    );
    final raw = jsonEncode(comment);
    final metadata = NaiImageMetadata.fromNaiComment({
      'Comment': raw,
      'Software': 'NovelAI',
      'Source': ImageSaveUtils.getModelSourceName(effective.model),
    }, rawJson: raw);
    // 快照不再进 PNG，内存元数据仍要带上供历史面板与详情页判定固定词。
    final withFixedTags = fixedTagUsageSnapshot == null
        ? metadata
        : metadata.withFixedTagUsageData(fixedTagUsageSnapshot.toJson());
    // 分区同样只在内存元数据里携带，供复用参数时恢复分区。
    final groups = _activePromptGroupSnapshot;
    return groups == null
        ? withFixedTags
        : withFixedTags.copyWith(promptGroupData: groups.toJson());
  }

  /// 请求里的角色取自面板时连同整个面板一起记下：角色名、未启用的角色与
  /// 分区不在图片元数据里，复用参数时靠它原样恢复。
  /// Whether the characters [params] carries are the ones the panel sends
  /// now: same prompts in the same order.
  bool _panelSends(ImageParams params) {
    final notifier = ref.read(characterPromptNotifierProvider.notifier);
    notifier.syncFixedTags();
    final panel = _convertCharactersToApiFormat(
      ref.read(characterPromptNotifierProvider),
    );
    final carried = params.characters;
    if (panel.length != carried.length) return false;
    for (var index = 0; index < panel.length; index++) {
      if (panel[index].prompt != carried[index].prompt ||
          panel[index].negativePrompt != carried[index].negativePrompt) {
        return false;
      }
    }
    return true;
  }

  CharacterPanelSnapshot? _characterPanelSnapshot(ImageParams params) {
    final config = ref.read(characterPromptNotifierProvider);
    if (config.characters.isEmpty) return null;
    return CharacterPanelSnapshot(
      config: config,
      sections: CharacterSectionStore.entriesFor(
        ref.read(localStorageServiceProvider),
        [for (final character in config.characters) character.id],
      ),
      sentPrompts: [
        for (final character in params.characters) character.prompt,
      ],
    );
  }

  /// 分区结构不写进 PNG，按结果图内容哈希写入旁路记录库。
  void _recordPromptGroups(List<Uint8List> images) {
    final snapshot = _activePromptGroupSnapshot;
    if (snapshot == null || images.isEmpty) return;
    unawaited(
      PromptGroupRecordStore().recordGeneratedImages(
        images: List.of(images),
        snapshot: snapshot,
      ),
    );
  }
}
