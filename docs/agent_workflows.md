# 智能体调查、提问与确认

## 职责边界

- `agent_research_instructions.dart` 维护默认角色调查策略，由 `buildAgentSystemPrompt` 组装。身份检索、标准标签核实、画廊外观证据复用现有工具，不在 Harness 中建立任务专属协议或第二份标签库。
- `search_tags` 经 `AgentTagLookup` 驱动与输入框联想相同的 `CompletionOrchestrator`（关闭联网与 LLM 翻译）：中文、拼音、自然码双拼、语义搜索与按上下文打分的相关标签都与编辑器一致；suggest 的 `categories` 对应联想弹窗的分类筛选，首个标签不是确切标签时返回其搜索结果并在 note 中说明。
- 角色知识问答本身不授权修改提示词或生成图片。联网关闭时保留该设置，使用可用的本地标签与画廊证据并说明限制；同一会话中已有的有效调查结果可以复用。
- 角色身份、稳定特征与版本服装分别处理。画廊中的姿势、背景、同图其他角色和画师风格不能直接当作角色固有特征。默认系统提示被用户整体覆盖时，自定义提示负责保留所需调查策略。

## 系统提示词组装

`agent_chat/services/agent_system_prompt.dart` 是聊天请求与设置预览的共同组装入口，沿用 Pi 将自定义正文与运行上下文分开的方式；不修改 Harness 的会话或工具协议。

- **补充要求**：内置正文 → 用户的自然语言要求 → 应用运行上下文。默认输入框为空，留空即使用内置正文。
- **替换正文**：用户正文 → 应用运行上下文。切换到此模式且草稿为空时，载入可编辑的内置正文；用户可以自行精简或重写，保存空正文也不会丢失运行上下文。
- **恢复默认**：只恢复当前模式的内容，不切换模式；补充模式清空自定义要求，替换模式重新载入内置正文，点击保存后生效。
- **内置正文**：默认身份、工具使用建议、NovelAI 写法与角色调查策略。它可以被替换，不含工作目录或 Skills 清单的设备快照。
- **NovelAI 写法**：先用 `search_tags` 查合适的 danbooru tag，没有合适的再写精简的英文短语；V4 起权重写成 `x.x::tags::`，范围 -3 到 3；要排除的具体内容写成正面提示词（或该角色提示词）里的负权重 tag，负面提示词只保留通用的画质与崩坏类内容，用户没要求不改。正文还说明固定词与质量词在发送时自动加入、`<词库名>` 是词库引用，以及生成失败应用已自动重试 5 次、不必再次提交。
- **运行上下文**：当前导出工作目录、联网可用性、启用且可由模型调用的 Skills 清单，以及生成准备/提交、提问与权限确认的应用协议。两种模式均由程序自动补充，权限仍由实际工具执行层强制检查。

**对话提示词**：会话“更多”菜单与 `/instructions` 打开编辑框，只对当前对话生效，留空即清除。组装时以 `<conversation_instructions>` 放在全局要求之后、运行上下文之前，两种模式都会加入，与全局要求冲突时以它为准；设置页预览只展示全局组装。内容存本机设置 `agent_chat_session_instructions:<会话 id>`（`AgentChatSessionInstructions`，上限与自定义提示词相同），不写进会话 JSONL、不参与云同步，删除会话时一并删除。切换会话时由会话控制器按目标会话 id 组装；运行中修改会在本轮结束后生效。

自定义文本按字面处理，没有模板替换语法，也不要求用户保留占位符。`{tag}`、`[tag]`、`1.3::tag::` 和 `-1::tag::` 是 NovelAI 权重语法示例。设置预览展示与实际请求相同的组装规则，结构化工具定义由 Provider 单独发送。

保存与云同步仍仅使用现有 `customSystemPrompt` 和 `systemPromptMode` 字段；自动上下文不写入自定义配置，不新增同步类型。旧自定义文本原样保留，旧客户端仍按旧版覆盖语义工作；跨设备恢复后，新客户端会重新组装本机上下文。旧文本中手写的目录或 Skills 不做猜测式删除，用户可在编辑器中清理。

## 提示词分区

分区模式下，`get_prompt_state` 返回各分区的 id、文本与启用状态；`edit_prompt_sections` 新增、改写、启停或移动分区，`remove_prompt_section` 删除分区并按删除类操作确认。`set_positive_prompt` / `set_negative_prompt` 在分区模式下不合并分区：追加和前置新增一个分区，替换只换掉启用的分区，停用分区原样保留。写入由 `PromptSectionState` 依次发出分区恢复请求、写入编辑器存档、更新生成提示词；生成页不在屏幕上时，打开后同样恢复。

角色提示词的分区由全局开关 `characterPromptsGroupedProvider` 决定，`get_prompt_state` 以 `character_editor_mode` 报告，分区模式下每个角色带自己的 `positive_sections` / `negative_sections`。`edit_prompt_sections` / `remove_prompt_section` 传 `character_id` 时改该角色的分区；`add_character` / `update_character` 可用 `prompt_sections` / `negative_prompt_sections` 按顺序给出全部分区，`update_character` 的 `prompt` 只替换启用的文字分区，停用分区与固定词分区保留。角色分区可以引用固定词（`fixed_tag_id`，文字跟随固定词，不能在此改写）；启用的角色引用启用的固定词时，这次生成主提示词不再带它，除非该分区 `keep_in_main`，`list_fixed_tags` 用 `claimed_by` 列出这些角色。写入由 `CharacterSectionState` 先存分区、再写角色提示词，并递增 `characterSectionsRevisionProvider`，已打开的角色编辑器据此改为显示新分区。角色库工具 `list_character_library`、`get_character_library_entry`、`add_character_from_library`、`save_character_to_library` 复用 `CharacterLibraryTransfer`，归入提示词权限域。

## 结构化提问

`ask_user_question` 接收非空 `questions` 数组，每题包含：

- `id`：请求内唯一的问题标识。
- `title`：完整问题。
- `options`：恰好三个有意义且实际可行的方向，每项包含唯一 `id`、`label` 与解释影响的 `description`。
- `recommended_option_id`：必须指向其中一个方向。界面显示推荐标记。

第四项“自定义”由界面统一补充，模型不能再加入占位选项。用户选择建议项后进入下一题；自定义项填写后进入下一题；最后检查整组答案再提交，可以返回修改。

通用组件 `UserQuestionFlow` 只依赖问题数据和提交/取消回调，不依赖 Riverpod、智能体、联网或权限。`AgentChatQuestionCard` 负责将其接到当前会话；`AgentUserQuestionController` 持有未完成工具调用，校验请求身份与答案完整性。过期提交、重复提交和无效答案不能完成当前请求。

问题等待期间退出手机对话不会自动作答，主界面入口显示问号与等待回答状态。新提问显示一次 Toast，Android 同时发送系统通知；点击通知打开对应提问，回答、超时或取消后撤销通知。Android 通知沿用运行开始时申请的系统通知权限；拒绝或禁用通知时明确提示，提问本身仍可在应用内完成。取消返回明确的 `cancelled` 结果；中止运行通过既有 `AbortSignal` 结束等待并释放监听器。整组问题默认等待 120 秒，可用 `timeout_seconds` 指定正整数秒数；到期自动提交全部推荐项（包括替换尚未提交的草稿选择），结果标记 `source: timeout_recommendation`，不构成删除或付费授权。倒计时由请求 owner 持有，退出页面不重置；提交、取消、中止会清理计时器。

问题表单与未提交答案是临时界面状态，不新增云同步数据类型。提交的答案走既有工具结果与会话持久化协议，沿用会话现有的备份范围。

## 权限和费用

信息提问与权限审批分开：`ask_user_question` 用于存在实质差异的用户偏好或歧义，不用于重复请求工具授权，也不要求用户代替工具查询事实。

权限的唯一执行判定仍是 `AgentToolPermissionCatalog` / `AgentToolPermissionController`：

- 完全访问下普通读写和页面状态移除（角色、当前参考、源图、草稿、已完成队列记录）直接执行；永久删除已保存数据的工具（Vibe/精准参考/词库条目与分类、固定词、待执行与失败队列任务，以及今后新增的 `delete_` 工具）和计费仍走审批。
- 生成先准备并取得实际 Anlas 估算；精确为零的提交不要求模型提供确认标志，在完全访问下不弹审批。
- 正数或未知费用仍走审批。付费提交携带原有 `confirmed=true`（重绘为 `confirm=true`）表达提交意图，该标志不能绕过应用审批。
- 不在聊天文本或结构化问题中先索要一次确认、随后又弹一次审批。
- 安全模式和写入前询问模式继续遵循其权限限制；已准备任务仍保持一次提交语义。

## 验证入口

使用 `scripts/test_affected.ps1` 运行对应源码的测试，必要时用 `-Include` 加入以下回归：

- `user_question_toolbox_test.dart`：参数、推荐项、过期答案、取消、中止与只读模式。
- `user_question_flow_test.dart`：逐题推进、自定义、返回修改、推荐标记和响应式可达性。
- `agent_chat_notifier_test.dart`：实际工具注册、等待答案与模型续跑。
- `generation_toolbox_test.dart`、`manual_inpaint_toolbox_test.dart`、`agent_tool_permission_controller_test.dart`：零费用、付费、重复提交与模式约束。
- `agent_system_prompt_test.dart`：策略组装与联网不可用时的边界。

提示策略测试能验证默认指令和工具契约，不能证明每个外部模型都必然遵循调查顺序；评估实际模型时应查看工具轨迹与引用依据。
