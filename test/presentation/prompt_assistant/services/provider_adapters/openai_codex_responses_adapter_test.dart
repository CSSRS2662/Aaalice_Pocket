import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/data/models/prompt_assistant/prompt_assistant_models.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/agent_protocol.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/provider_adapters/openai_codex_responses_adapter.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/provider_adapters/prompt_assistant_adapter.dart';

import '../../../../helpers/chatgpt_codex_fakes.dart';

final _provider = ProviderPreset.chatgptCodex.createConfig();
const _responses = '/backend-api/codex/responses';

List<Map<String, Object?>> _reply(String text) => [
  {'type': 'response.output_text.delta', 'delta': text},
  {
    'type': 'response.completed',
    'response': {
      'output': <Object>[],
      'usage': {'input_tokens': 3, 'output_tokens': 1, 'total_tokens': 4},
    },
  },
];

AgentChatRequest _request({String? apiKey, int? maxOutputTokens}) =>
    AgentChatRequest(
      sessionId: 'session-1',
      provider: _provider,
      model: 'gpt-5.5',
      systemPrompt: 'Be brief.',
      messages: [UserMessage.text('hello')],
      tools: const [
        Tool(
          name: 'get_prompt_state',
          description: 'Read the prompt.',
          parameters: {'type': 'object', 'properties': <String, Object>{}},
        ),
      ],
      apiKey: apiKey,
      maxOutputTokens: maxOutputTokens,
    );

void main() {
  test('agent requests use the Codex endpoint, headers and body', () async {
    final http = RoutedHttpAdapter({_responses: (_) => sseBody(_reply('Hi'))});
    final events = await const OpenAiCodexResponsesAdapter()
        .completeAgent(
          dio: Dio()..httpClientAdapter = http,
          request: _request(apiKey: fakeChatGptToken(), maxOutputTokens: 500),
          cancelToken: CancelToken(),
        )
        .toList();

    expect(events.whereType<AgentWireTextDelta>().single.delta, 'Hi');
    expect(events.last, isA<AgentWireFinish>());
    final sent = http.requests.single;
    expect(
      sent.options.uri.toString(),
      'https://chatgpt.com/backend-api/codex/responses',
    );
    final headers = sent.options.headers;
    expect(headers['Authorization'], 'Bearer ${fakeChatGptToken()}');
    expect(headers['chatgpt-account-id'], 'acc_1');
    expect(headers['OpenAI-Beta'], 'responses=experimental');
    expect(headers['originator'], 'aaalice_pocket');
    expect(headers['session-id'], 'session-1');
    final body = sent.data! as Map<String, dynamic>;
    expect(body['store'], isFalse);
    expect(body['stream'], isTrue);
    expect(body.containsKey('max_output_tokens'), isFalse);
    expect(body['instructions'], 'Be brief.');
    expect(body['text'], {'verbosity': 'low'});
    expect(body['include'], ['reasoning.encrypted_content']);
    expect(body['prompt_cache_key'], 'session-1');
    expect(body['tool_choice'], 'auto');
    expect(body['parallel_tool_calls'], isTrue);
    final tool = (body['tools'] as List).single as Map;
    expect(tool['name'], 'get_prompt_state');
    expect(tool.containsKey('strict'), isTrue);
    expect(tool['strict'], isNull);
  });

  test('without a login no request is sent', () async {
    final http = RoutedHttpAdapter({});
    final events = await const OpenAiCodexResponsesAdapter()
        .completeAgent(
          dio: Dio()..httpClientAdapter = http,
          request: _request(),
          cancelToken: CancelToken(),
        )
        .toList();
    expect(
      (events.single as AgentWireError).message,
      OpenAiCodexResponsesAdapter.loginRequiredMessage,
    );
    expect(http.requests, isEmpty);
  });

  test('a usage limit names the plan and the local reset time', () async {
    final now = DateTime(2026, 10, 15, 9);
    final reset = now.add(const Duration(minutes: 90));
    final http = RoutedHttpAdapter({
      _responses: (_) => jsonBody({
        'error': {
          'code': 'usage_limit_reached',
          'plan_type': 'PLUS',
          'resets_at': reset.millisecondsSinceEpoch ~/ 1000,
        },
      }, status: 429),
    });
    final events = await OpenAiCodexResponsesAdapter(clock: () => now)
        .completeAgent(
          dio: Dio()..httpClientAdapter = http,
          request: _request(apiKey: fakeChatGptToken()),
          cancelToken: CancelToken(),
        )
        .toList();
    final error = events.whereType<AgentWireError>().single;
    expect(error.message, contains('(plus plan)'));
    expect(error.message, contains('10:30'));
    expect(error.message, contains('~90 min'));
    expect(error.transient, isFalse);
  });

  test('one-shot assistant tasks read the stream', () async {
    final http = RoutedHttpAdapter({
      _responses: (_) => sseBody([..._reply('{"a"'), ..._reply(':1}')]),
    });
    final text = await const OpenAiCodexResponsesAdapter().complete(
      dio: Dio()..httpClientAdapter = http,
      request: PromptAssistantRequest(
        sessionId: 'assistant',
        provider: _provider,
        model: 'gpt-5.4-mini',
        systemPrompt: 'Translate.',
        userParts: [
          const PromptAssistantTextPart('猫'),
          PromptAssistantImagePart(
            bytes: Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png',
          ),
        ],
        apiKey: fakeChatGptToken(),
        responseFormat: PromptAssistantResponseFormat.jsonObject,
        responseTimeout: const Duration(minutes: 15),
      ),
      cancelToken: CancelToken(),
    );
    expect(text, '{"a":1}');
    // The user's response timeout, not the agent's fixed wait.
    expect(
      http.requests.single.options.receiveTimeout,
      const Duration(minutes: 15),
    );
    final body = http.requests.single.data! as Map<String, dynamic>;
    expect(body['text'], {
      'verbosity': 'low',
      'format': {'type': 'json_object'},
    });
    final content = ((body['input'] as List).single as Map)['content'] as List;
    expect(content.first, {'type': 'input_text', 'text': '猫'});
    expect(
      (content.last as Map)['image_url'],
      'data:image/png;base64,${base64Encode([1, 2, 3])}',
    );
    expect(body.containsKey('tools'), isFalse);
  });

  test('the model list comes from the catalog', () async {
    final models = await const OpenAiCodexResponsesAdapter().fetchModels(
      dio: Dio(),
      provider: _provider,
      apiKey: null,
    );
    expect(models, containsAll(['gpt-5.4', 'gpt-5.5', 'gpt-5.3-codex-spark']));
  });
}
