import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../../core/agent/agent_types.dart';
import '../../../../data/models/prompt_assistant/prompt_assistant_models.dart';
import '../../../../data/services/chatgpt_codex/chatgpt_codex_credentials.dart';
import '../../models/agent_protocol.dart';
import '../../models/pi_reasoning_model_catalog.dart';
import 'openai_responses_adapter.dart';
import 'prompt_assistant_adapter.dart';

/// ChatGPT subscription models through the Codex backend, ported from Pi's
/// `api/openai-codex-responses.js` over SSE. The body is the Responses API
/// with the Codex differences: always streamed and unstored, no output token
/// cap, encrypted reasoning always included.
class OpenAiCodexResponsesAdapter extends OpenAiResponsesAdapter {
  const OpenAiCodexResponsesAdapter({DateTime Function()? clock})
    : _clock = clock;

  final DateTime Function()? _clock;

  static const loginRequiredMessage =
      'ChatGPT login required: sign in to this provider under Settings > '
      'Integrations.';

  static final _usageLimitCode = RegExp(
    'usage_limit_reached|usage_not_included|rate_limit_exceeded',
    caseSensitive: false,
  );

  /// The backend lists no models; offer the ones Pi's registry knows.
  @override
  Future<List<String>> fetchModels({
    required Dio dio,
    required ProviderConfig provider,
    required String? apiKey,
  }) async => [...?piReasoningModelCatalog['openai-codex']?.keys]..sort();

  /// The backend only streams, so one-shot assistant tasks read the stream.
  @override
  Future<String> complete({
    required Dio dio,
    required PromptAssistantRequest request,
    required CancelToken cancelToken,
  }) async {
    final text = StringBuffer();
    await for (final event in completeAgent(
      dio: dio,
      request: _CodexTextRequest.from(request),
      cancelToken: cancelToken,
    )) {
      switch (event) {
        case AgentWireTextDelta(:final delta):
          text.write(delta);
        case AgentWireError(:final message):
          throw StateError(message);
        default:
          break;
      }
    }
    return text.toString();
  }

  @override
  Stream<AgentWireEvent> completeAgent({
    required Dio dio,
    required AgentChatRequest request,
    required CancelToken cancelToken,
  }) async* {
    final token = request.apiKey?.trim() ?? '';
    if (token.isEmpty || ChatGptCodexClaims.parse(token) == null) {
      yield const AgentWireError(loginRequiredMessage);
      return;
    }
    yield* super.completeAgent(
      dio: dio,
      request: request,
      cancelToken: cancelToken,
    );
  }

  /// One-shot assistant tasks wait as long as the user configured.
  @override
  Duration? agentReceiveTimeout(AgentChatRequest request) =>
      request is _CodexTextRequest
      ? request.responseTimeout
      : super.agentReceiveTimeout(request);

  @override
  String agentEndpoint(ProviderConfig provider) =>
      '${ChatGptCodexAuth.backendBase(provider.baseUrl)}/codex/responses';

  @override
  Map<String, dynamic> agentHeaders(AgentChatRequest request) {
    final token = request.apiKey!.trim();
    return {
      'Authorization': 'Bearer $token',
      'chatgpt-account-id': ChatGptCodexClaims.parse(token)!.accountId,
      'originator': ChatGptCodexAuth.originator,
      'User-Agent': ChatGptCodexAuth.userAgent,
      'OpenAI-Beta': 'responses=experimental',
      'accept': 'text/event-stream',
      'Content-Type': 'application/json',
      'session-id': request.sessionId,
      'x-client-request-id': request.sessionId,
    };
  }

  @override
  Map<String, dynamic> agentPayload(AgentChatRequest request) {
    final payload = super.agentPayload(request)..remove('max_output_tokens');
    final instructions = request.systemPrompt.trim();
    final tools = payload['tools'];
    return {
      ...payload,
      'store': false,
      'stream': true,
      'instructions': instructions.isEmpty
          ? 'You are a helpful assistant.'
          : instructions,
      'text': {
        'verbosity': 'low',
        if (request is _CodexTextRequest && request.jsonObject)
          'format': {'type': 'json_object'},
      },
      'include': ['reasoning.encrypted_content'],
      'prompt_cache_key': request.sessionId,
      'tool_choice': 'auto',
      'parallel_tool_calls': true,
      if (request.serviceTier case final tier?) 'service_tier': tier,
      // Pi leaves strict validation off for Codex tools.
      if (tools is List)
        'tools': [
          for (final tool in tools)
            if (tool is Map<String, dynamic>) {...tool, 'strict': null},
        ],
    };
  }

  @override
  AgentWireError agentWireError(Object error, ProviderConfig provider) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final body = error.response?.data;
      final detail = body is Map ? body['error'] : null;
      final code = detail is Map ? '${detail['code'] ?? detail['type']}' : '';
      if (status == 429 || _usageLimitCode.hasMatch(code)) {
        return AgentWireError(_usageLimitMessage(detail is Map ? detail : null));
      }
      if (status == 401) {
        return const AgentWireError(
          'ChatGPT login expired or was revoked: sign in again under '
          'Settings > Integrations.',
        );
      }
    }
    return super.agentWireError(error, provider);
  }

  /// Pi's friendly limit message, with the reset time in local time.
  String _usageLimitMessage(Map<dynamic, dynamic>? detail) {
    final plan = detail?['plan_type'];
    final planText = plan is String && plan.isNotEmpty
        ? ' (${plan.toLowerCase()} plan)'
        : '';
    final resetsAt = detail?['resets_at'];
    if (resetsAt is! num) return 'You have hit your ChatGPT usage limit$planText.';
    final now = (_clock ?? DateTime.now)();
    final reset = DateTime.fromMillisecondsSinceEpoch(
      (resetsAt * 1000).round(),
      isUtc: true,
    ).toLocal();
    final minutes = reset.difference(now).inMinutes.clamp(0, 1 << 30);
    final format = reset.difference(now) < const Duration(hours: 20)
        ? DateFormat.Hm()
        : DateFormat('MM-dd HH:mm');
    return 'You have hit your ChatGPT usage limit$planText. It resets at '
        '${format.format(reset)} (in ~$minutes min).';
  }
}

/// A one-shot assistant task sent as a single user turn.
class _CodexTextRequest extends AgentChatRequest {
  _CodexTextRequest.from(PromptAssistantRequest request)
    : jsonObject =
          request.responseFormat == PromptAssistantResponseFormat.jsonObject,
      responseTimeout = request.responseTimeout,
      super(
        sessionId: request.sessionId,
        provider: request.provider,
        model: request.model,
        systemPrompt: request.systemPrompt,
        messages: [
          UserMessage(
            content: [
              for (final part in request.userParts)
                if (part is PromptAssistantTextPart)
                  UserTextContent(part.text)
                else if (part is PromptAssistantImagePart)
                  UserImageContent(
                    ImageContent(
                      source: ImageSource.base64(
                        mimeType: part.mimeType,
                        base64Data: base64Encode(part.bytes),
                      ),
                    ),
                  ),
            ],
          ),
        ],
        tools: const [],
        apiKey: request.apiKey,
        reasoningRequest: request.reasoningRequest,
      );

  final bool jsonObject;
  final Duration responseTimeout;
}
