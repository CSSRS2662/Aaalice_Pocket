# ChatGPT（Codex）订阅登录

智能体与提示词助手可以用 ChatGPT 账号登录，通过 Codex 后端使用订阅额度，不需要 API Key。实现移植自 Pi（`@earendil-works/pi-ai` 0.85.0，与 `tool/agent/pi_reasoning_source_lock.json` 锁定的版本一致）。

## 组成

| 部分 | 位置 | 来源 |
|---|---|---|
| 服务商 | `ProviderPreset.chatgptCodex`，协议 `ProviderProtocol.openaiCodexResponses`（`usesChatGptLogin`） | — |
| 登录 | `lib/data/services/chatgpt_codex/chatgpt_codex_oauth_client.dart`、`chatgpt_codex_callback_server.dart` | Pi `auth/oauth/openai-codex.js`、`device-code.js` |
| 凭据 | `ChatGptCodexAccountNotifier`（`chatgpt_codex_account_provider.dart`），存于 `SecureStorageService`，键前缀 `chatgpt_codex_credentials_` | — |
| 请求 | `OpenAiCodexResponsesAdapter`，基于 `OpenAiResponsesAdapter` 的端点、请求头、请求体与错误钩子 | Pi `api/openai-codex-responses.js`（只移植 SSE，不含 WebSocket） |
| 模型 | `piReasoningModelCatalog['openai-codex']`，由 `tool/agent/generate_pi_reasoning_catalog.dart` 生成 | Pi `providers/data/openai-codex.json` |
| 额度 | `ChatGptCodexUsage`、`ChatGptCodexUsageInterceptor`、`chatGptCodexUsageProvider`；智能体顶栏 `ChatGptCodexQuotaSlot` | Codex CLI 0.144 的 `x-codex-*` 响应头与 `/wham/usage` |

## 登录

- **设备码**（手机默认推荐）：`/api/accounts/deviceauth/usercode` 取一次性代码，用户在 `https://auth.openai.com/codex/device` 输入；轮询 `/api/accounts/deviceauth/token`（403/404 与 `deviceauth_authorization_pending` 视为等待，`slow_down` 间隔加 5 秒，15 分钟超时），拿到授权码后在 `/oauth/token` 兑换。账号未开启设备码登录时 `usercode` 返回 404。
- **浏览器**：PKCE（复用 `OAuthPkce`），回调固定为 `http://localhost:1455/auth/callback`，这是 Codex 公共客户端唯一接受的地址；端口被占用或应用在后台被回收时，用户可粘贴浏览器地址栏的网址完成登录。
- 访问令牌在到期前 5 分钟刷新，同一服务商的并发请求共用一次刷新；刷新被拒且令牌已过期时标记为需要重新登录，网络失败时继续使用未过期的令牌。
- 智能体通过 `AgentOptions.getApiKey` 在每次调用模型前取令牌；提示词助手、反推等经 `PromptAssistantConfigNotifier.getProviderApiKey`。

## 请求差异

与 OpenAI Responses 相比：端点为 `<base>/codex/responses`；请求头带 `chatgpt-account-id`（取自令牌声明）、`originator`、`OpenAI-Beta: responses=experimental`、`session-id`；请求体固定 `store:false`、`stream:true`，不发 `max_output_tokens`，始终包含 `reasoning.encrypted_content`，工具的 `strict` 为 null。后端只流式返回，提示词助手的一次性任务读取流并使用用户设定的等待时长。用量超限时错误信息给出套餐与本地重置时间。

## 额度

- 每次 Codex 响应（含错误响应）的 `x-codex-primary-*`、`x-codex-secondary-*` 头由拦截器记录，按账号保存在内存，不持久化、不同步。
- 打开额度详情或顶栏首次显示时读取 `GET /wham/usage`，同一账号 60 秒内不重复读取，详情页的刷新按钮可强制读取。
- 窗口按服务端给的长度命名（如 5 小时、每周），不写死；百分比显示剩余值，重置时间换算为本机时区。
- 顶栏按标题行可用宽度选择密度：两个窗口、只显示最紧的窗口、只显示图标。

## 限制

- 使用 Codex CLI 的公共 client ID 与未公开的 ChatGPT 后端，服务端可能随时变化；`originator` 使用本应用自己的标识。
- 凭据只保存在本机安全存储，服务商配置本身随提示词助手配置同步，换设备需重新登录。

## 验证入口

- `test/data/services/chatgpt_codex/`：设备码轮询、兑换、刷新、浏览器授权参数、回调服务器、额度解析与拦截器。
- `test/presentation/prompt_assistant/providers/chatgpt_codex_account_provider_test.dart`：刷新时机、并发共用、吊销与登出。
- `test/presentation/prompt_assistant/services/provider_adapters/openai_codex_responses_adapter_test.dart`：端点、请求头、请求体、超限错误、一次性任务。
- `test/presentation/agent_chat/widgets/chatgpt_codex_quota_pill_test.dart`、`agent_chat_header_test.dart`、`test/presentation/screens/settings/widgets/chatgpt_codex_login_sheet_test.dart`：额度胶囊、详情、顶栏宽度与登录面板。
