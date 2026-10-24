# Android 分支与上游的分叉清单

本文件记录 `android-custom` 相对上游有意保留的差异，以及从上游移植改动时的处理规则。移植前先读此表，移植后更新“最近一次移植”。

## 分支与基线

- 上游：`Aaalice233/Aaalice_NAI_Launcher`，2026-09-15 起由协作者接手维护，仍在持续更新。
- 自 2026-10-19 起不再整体合并上游：逐条审阅上游提交，只移植对手机端改动小、收益大的修复与功能，以 `cherry-pick -x` 保留来源；上游以后出了对手机有用的功能，看它改了什么再移植。
- 前端设计与界面以本分支为准：上游新增或修改的界面与本分支设计冲突时保留本分支，只吸收不改变外观的行为修复（溢出、滚动、命中区、限额提示等）；断言上游专属界面的测试改写，不为测试改本分支界面。
- 全部定制在 `android-custom`。每次移植前创建 `backup/android-custom-before-port-YYYYMMDD`，在独立本地分支移植验证后再快进 `android-custom`。
- `android-custom` 只在发布大版本时以快进方式推送到 fork（`CSSRS2662/Aaalice_Pocket`）的 `main`，推送前确认，不强制推送；自用小版本的提交只留在本地。
- 工具链以 `tool/android_build_environment.lock.json` 为准；上游升级 Flutter 时同步更新该文件。

## 版本号与发布

- 自 2026-10-19 起使用本分支自己的版本号，不再跟随上游的 `4.x.x-custom.N`（最后一个旧格式发布版是 `4.2.1-custom.23`）。格式为 `<X.Y.Z>[-dev.<N>]+<构建号>`；构建号每次打包加 1、持续递增，保证覆盖安装；安装包名为 `Aaalice_Pocket_<版本名>_arm64.apk`。
- `X.Y.Z` 是发布版：下一个发布版为 `1.0.0`，之后 `1.1.0`、`1.2.0`……（只修问题的发布递增 Z）。只有决定发布时才连同代码一起推送，打 `pocket-v<版本名>` 标签，在 GitHub Releases 发布。标签不用 `v` 开头，避免触发上游继承的 Release 工作流，也不与上游标签重名。
- 两次发布之间的打包都是自用包，不发布也不推送代码：首个发布版之前用 `0.9.0-dev.1`、`0.9.0-dev.2`……；发布 `1.0.0` 后自用包从 `1.1.0-dev.1` 起，发布时去掉 `-dev.N`。
- 从上游移植改动不影响版本号。

## 有意分叉与合并规则

| 领域 | 本分支做法 | 合并时的规则 |
| --- | --- | --- |
| 包名与品牌 | `com.cssrs2662.aaalicepocket`，名称、图标、启动页为 Aaalice Pocket；图标是口袋里的猫耳像素少女（自适应图标前景 + 奶油色底 `#FFF9ED` + 主题图标），启动页只播放一次进入动画（`SplashIntroAnimation` 播放 `assets/splash/pocket_intro.gif`，加载更久时停在最后一帧）并只显示转圈，`AppBootstrap` 等动画播完再进入主界面；原生启动窗口、图标底色与 Flutter 启动页同色 | 保留本分支；MethodChannel 名称与上游保持一致，开发与验收脚本使用新包名；上游修改 `splash_screen.dart`、`app_bootstrap.dart` 或安卓启动主题时保留本分支启动页、`_splashKey` 与动画等待，不恢复进度条和任务文字 |
| 应用内更新 | 整套移除（检查、下载、安装、弹窗、横幅） | 上游对更新模块的修改一律丢弃；上游新测试中对更新 provider 的 override 一并删除 |
| 社区入口 | 导航与“更多”面板不显示 GitHub/Discord | `CommunityLinks` 常量保留，上游其他代码仍在引用 |
| 网络 | 共享连接工厂；Android 不使用应用级代理，交给系统/VPN | 保留工厂；上游的请求形态（浏览器请求头、JS 兼容 JSON）叠加在工厂创建的 Dio 上 |
| 设置 | Android 隐藏“网络”“快捷键”分类 | 保留，按能力矩阵判断 |
| 补全 | 中文否定与多关键词扩展；E5 语义补全（多视图 int8 包：基线文档 + AME 译名/别名/注释，标签取最高分，`E5VectorIndex`）；随包 AME 中文词库 `AmeZhLexicon` 提供中文别名反查并作为翻译的最后一级兜底，并合并本项目为无中文标签写的补充译名（`tool/zh_lexicon/pocket_translations.json` → `pocket_lexicon.json.gz`，同时追加为 E5 视图）；Danbooru 已改名的旧标签经 `TagRenameFolder` 并入新名（`renamedTags` 只取 Danbooru 已不存在的别名，排除 e621 在两个现存 Danbooru 标签之间的别名），新名无中文时借用旧名译名；非 AI 搜索增强（`lib/core/autocomplete/lexical/`：同音/模糊音、全拼、自然码双拼、首字母、近似中文、中文拆词匹配英文 tag、英文纠错与词形，上下文共现与本机使用习惯排序），上下文联想（`RelatedTagScorer` 按光标前后最多 6 个词综合共现与提升度、冲突降权；`TagPairHistory` 本机搭配学习；只在选中补全、分词与联想键后续联想，`showRelated` 只看所选词；`CompletionExclusionScope` 排除其他分区与固定词；补全弹窗重做为按匹配顺序换行、两端对齐的注音词块（`CompletionTile` / `CompletionRowsLayout`，Roboto Condensed），标题栏不回显输入、直接放分类按钮多选筛选（`CompletionCategoryFilter`：联想经 `CompletionQuery.relatedCategories` 读主导词的全部共现行，打字补全经 `typedCategories` 在基础词库与中文词典中按分类查询，在线结果同样过滤），底栏来源状态兼作来源圆点图例，只留圆点与图标；长按词块多选，`CompletionMultiSelection` 按选中顺序经 `PromptTokenParser.applyAll` 一次写入，Enter、软键盘换行与“插入”写入，返回与 Esc 先退出多选），数据由 `tool/search_lexicon/` 从固定版本的 MIT 来源生成，本机索引在后台构建；智能体 `search_tags` 经 `AgentTagLookup` 复用同一联想流程（不联网），相关标签可按角色、作品、一般分类筛选 | `e5CompletionSourceProvider` 放在 `e5_completion_source.dart`；只在上游的 `autocompleteServicesProvider` 中补 `semanticSource`、`supplementalSources`、`rankingSignals`、`tagCategory`、`relatedCategoryCounts`、`typedCategoryCounts` 六行；上游修改 `CompletionRanker` 时保留新增匹配方式的优先级（全部在字面匹配之后）与 `boosts` 参数；上游修改 `FastTagService` 时保留 `lexicon`、`renames` 参数与其在搜索、解析末尾的位置；上游修改 `CompletionOrchestrator` 或词法索引时保留 `foldRenamedTags` 与 `pocketLexiconGz`；上游更新 E5 包后重跑 `append_pocket_views_test.dart`；上游修改 `AutocompleteWrapper` 的插入、按键、文本监听或返回处理时，保留多选（`_picks`、`PopScope`、`AutocompleteOverlayHandle.hostHandlesBack`）与 `applyAll`；上游修改 `PromptTokenParser` 的权重语法剥离、`AliasParser`、`PromptLiteralScanner`、`PromptEditDocument` 的圆括号处理或 `SdToNaiConverter` 时，保留“标签自带符号不算语法”的规则（`_tagBounds`、颜文字的尖括号与圆括号、`名称_(xxx:1999)` 限定词）及对应测试 |
| Prompt | 分组编辑（`PromptGroupGrid` 等高卡片网格：轻击在 `showPromptGroupEditSheet` 底部面板编辑、长按拖动排序、长按菜单、× 两次点按删除并可撤销；编辑页顶行按宽度收纳 Tag 切换与“更多”，底栏末端为“联想”（hub）与“分词”（剪刀）键，补全弹窗底栏同有剪刀胶囊，分词共用 `PromptTokenParser.insertSeparator`；`PromptTagModeToggle` 改为与正负切换同款的单键）、权重滑条、移动端工作台、长按权重工具条；移动端“角色 / 固定词 / 质量词”合为 `PromptRoleSegmentGroup`，各按钮新增 `segment` 呈现；智能体提示词约定 tag 优先（先 `search_tags`）、V4 起写 `x.x::tags::`（-3 到 3）、排除内容用正面负权重、负面提示词保持通用，并说明固定词自动加入与 `<词库名>` 引用；`PromptTag` 的权重范围与权重工具条统一为 -3 到 3，负权重写回数值语法；每个对话可设本机保存的对话提示词（`AgentChatSessionInstructions`，组装为 `<conversation_instructions>`，不进 Harness 会话文件）；智能体按分区读写：`get_prompt_state` 返回分区，`edit_prompt_sections` / `remove_prompt_section` 改单个分区（带 `character_id` 时改角色分区），分区模式下写提示词不合并分区，写入经 `PromptSectionState` 走分区恢复请求；角色工具拆在 `character_toolbox.dart`，角色分区经 `CharacterSectionState`，另有角色库工具 | 保留；上游修改这些按钮的桌面外观时照常合并，`segment` 分支保持不变；上游改智能体提示词或角色工具时保留分区分支，角色工具改动落到 `character_toolbox.dart` |
| 分组持久化 | `PromptGroupRecordStore` 按结果图内容哈希记录分区，不写进 PNG；复用参数时按标签比对（`PromptGroupRestoreRequest.samePromptTags`）后恢复，请求用后即清 | 与上游固定词记录一致；解析时在 `ImageMetadataService` 挂载，旧版写进 PNG 的 `aaalice_prompt_groups` 仍可读取且优先 |
| 图片菜单 | “保存 → 复用参数 → 复用种子 → 收藏”开头（本轮图不含复用参数），无 Krita/Discord 项；本地画廊、智能体图片与在线画廊 AI TAG 图都能直接复用种子（`reuseImageSeed`）；收藏状态按文件共享（`imageFavoriteStatusProvider`，只由 `LocalGalleryNotifier` 写入），成功切换不弹提示；“更多 → 读取图片元数据”选图后打开拖放与分享导入共用的图片用途对话框，先显示提示词与参数，首项“复用参数”（`drop_extractMetadata`）进入 `ImageMetadataImportWorkflow` | 与上游新增的复制、删除等操作合并，危险操作排在最后；存盘复用上游 `GeneratedImageFileLink`；上游新增收藏入口时走 `LocalGalleryNotifier.toggleFavorite` 或 `toggleGeneratedImageFavorite` |
| 词库与固定词 | 词库页重做：手机为搜索 + 分组筛选条（`tag_library_group_bar.dart`）+ 按分组分节的两列紧凑卡片（`tag_library_sections.dart` 纯函数分节、`tag_library_sections_view.dart`、`entry_card.dart`），预览图缺省时显示分组图标（`widgets/tag_library/library_group_style.dart`：20 个按名称识别的预设与通用图标）；详情面板 `tag_library_entry_sheet.dart`、多选浮动条 `tag_library_selection_bar.dart`、分组管理与新建 `tag_library_group_manager.dart` / `tag_library_group_create_sheet.dart`，页面命令集中在 `tag_library_actions.dart`；发送到主提示词改为追加（`PendingPromptNotifier.appendToMainPrompt`、`PromptInputController.appendPrompt`，分组模式新增分区）并留在词库给出“去生成”；排序与“收藏置顶”持久化，名称排序用随包拼音表（`name_sort_key_provider.dart`）；预览图选取与文件管理抽到 `tag_library_thumbnail_store.dart`。固定词管理为三列名称网格（`fixed_tag_chip.dart` 选中为 `primaryContainer` + 主题色描边，名称下标出后缀 / 权重 / 联动）、排序面板（`fixed_tags_sort_provider.dart`、`fixed_tags_ordering.dart`，常用分数 `fixed_tag_usage_provider.dart` 由生成完成时记录、只存本机）、详情增加分组、权重加减与使用记录；固定词分组跟随词库（`reconcileFixedTagCategories`，词库移动条目、删除分组、导入后同步）；列数偏好已移除 | 上游修改词库页、`entry_card.dart`、`fixed_tags_columns.dart`、`fixed_tag_entry_tile.dart`、`fixed_tags_link_layer.dart` 时按本分支结构落位，不恢复列数、视图切换、行列表与连线；联动在对话框里经详情进入 `showFixedTagLinkManager(showAllCandidates: true)`；上游修改 `PromptInputCoordinator.consumePendingPrompt` 时保留 `mainPrompt` 追加分支；侧栏 `fixed_tags_sidebar.dart` 照常合并 |
| 触屏一致性 | 桌面专属入口在触屏补等价路径：在线画廊详情标签长按出菜单（`SimpleTagChip.onMenu`）、Vibe 菜单另列“替换现有 Vibe”、智能体结果图片触屏常驻“更多”；滚轮调权重与生成页布局设置、跟随鼠标、看图左右箭头、拖动改数在触屏隐藏；`ShortcutTooltip` 等在不支持快捷键配置的平台不显示组合键；说明文案按输入方式取 `*Touch` 版本；`usesDesktopGenerationLayout` 让触屏矮屏（手机横屏）保留工作台；查看器手指单击切换工具栏、下滑关闭（`DetailSwipeDismissController`）；文本选择菜单“相关标签”经 `AutocompleteOverlayHandle.showRelated` 触发；智能体工具按平台能力注册（没有 Krita 桥时不提供 Krita 工具），`save_generated_image` 与保存按钮一致写入系统相册，`navigate_application` 的设置分区跟随设置页、可切换工作台页签 | 上游新增右键、悬停或快捷键交互时同步补触屏入口与触屏文案；上游修改 `generation_screen.dart` 的断点判断时保留 `usesDesktopGenerationLayout`；上游新增智能体工具时在注册表按平台能力决定是否提供 |
| 主题 | 只保留 Pocket 一套主题的浅色与深色，删除 16 套预设及其配色、字体、形状、动效预设；设置改为“浅色 / 深色 / 跟随系统”，新键 `theme_mode` 参与云同步；中性纯白 / 炭黑底色，强调色可选预设或自定义（`accent_color`，参与云同步）；输入框底色取画布与分组中更深的一层；`appBarTheme` 固定 surface 色面，内容滚到顶栏下方不变色 | 上游对主题预设与模块预设的修改一律丢弃；上游测试引用 `GrungePalette` 等旧配色时改用 `PocketPalette`；`AppTheme.getTheme` 只接收明暗、字体与强调色 |
| 移动端生成页 | 工作台结构：图像、提示词、参数、参考、历史页签，页签等分不滚动、可左右滑动切换；顶栏左侧为相邻的模型与尺寸（`MobileSizeMenu`，只选不改），右端为额度胶囊（`MobileQuotaPill`：闪电 + 体力百分比、`AnlasIcon` + 余额）；全局底栏只有“抽卡 / 加入队列 / 智能体 / 队列 / 生成”一行，骰子点按随机提示词、长按开关抽卡模式（`RandomModeToggle.tapGeneratesPrompt`）；提示词页底部以确认式清空（`PromptClearAllButton`）取代随机按钮（`clearAllInsteadOfRandom`）；提示词页控制区压成一行纯图标，透明背景移到图像页信息条与参数页；模型只在顶栏菜单切换，`ParameterPanelContent.generation` 不含模型；Variety+ 从 CFG 标题移出，成为带说明的独立分节（`VarietyPlusSection`，桌面面板共用）；页签点按无水波纹；步数、CFG、CFG 重缩放用 `SteppedSlider`（−/+ 与输入）；移除参数/历史抽屉、折叠提示词条与上下滑手势 | 上游对 `mobile_generation_*` 的修改按工作台结构重新落位，不恢复抽屉与手势；桌面布局照常合并 |
| 图库与历史 | 本地画廊、精准参考库、Vibe 库工具栏分标题、搜索、范围三行，精准参考库与 Vibe 库有“全部 / 收藏”一键切换（本地画廊只放收藏，没有这个切换，相簿区也没有收藏行），低频操作收进“更多”菜单；`GalleryLibraryToolbar` 新增 `titleActions`、`filters` 插槽与 `GalleryLibrarySearchAction`；范围控件集中在 `gallery_scope_controls.dart`；本地画廊、生成历史、精准参考库、Vibe 库及其选择器缩略图改为按宽高比的瀑布流（`LibraryMasonryGrid`，复用在线画廊的 `OnlineGalleryMasonryLayoutSnapshot`）；手机平台（`prefersContinuousLibraryScrolling`）去掉分页条：本地画廊 `loadMore` 追加并按已加载范围重取，Vibe 与精准参考库连续显示全部，均可下拉刷新（`LibraryScrollActions`，在线画廊同样）；长按拖动多选（`CardDragSelect` / `CardDragSelectTarget`） | 上游对 `local_gallery_toolbar.dart`、`gallery_grid.dart`、`history_panel.dart` 的修改按新结构落位；上游修改 `online_gallery_masonry_layout.dart` 时同步检查画廊与历史排版；上游修改 `LocalGalleryNotifier.loadPage` 时保留已加载范围的重取逻辑，桌面分页照常合并 |
| 生成重试与保存 | 生图请求失败后立即重试，每个请求最多 5 次（`ImageGenerationCoordinator.defaultMaxRetries`），流式与非流式共用这 5 次，用完直接报错；每次重试发出 `GenerationRetrying`，生成中的卡片显示“重试 n/5”（`StreamPreviewSlot.retryAttempt`，新预览到来时保留），手机生成按钮显示“取消 · 重试 n/5”，重试时清掉失败那次的预览与进度；参数错误、未登录、Anlas 不足等重试也不会成功的 4xx 不重试（`isRetryableGenerationError`，408、429 除外），429 并发占用每 3 秒再试、最多 90 秒，不占次数（等待经 `generationRetryWaitProvider`，测试覆盖为不等待）。保存只进系统相册（`SystemAlbum`：Android 为 MediaStore `Pictures/Aaalice NAI Launcher`，其他平台为下载目录里的同名文件夹），按来源字节的内容哈希在本机设置 `system_album_saves_v1` 记下位置（不同步）；判重只看目标文件夹：记录的位置还在（`imageExists`），或文件夹里有内容相同的图（`findImage`：MediaStore 按 `RELATIVE_PATH` 与字节数筛选，只对同大小的候选算 SHA-256；未申请读取权限，只能看到本次安装写入的图），都算重复：详情页、预览、批量、卡片、打码/水印编辑器与 DLSS 的手动保存遇到重复不写，以 `ActionNotice` 底部深色通知提供“依然保存”（`allowDuplicate`），自动保存直接跳过，日志为 `[AlbumSave]`。收藏是写进图库的唯一入口（`GeneratedImageFileLink` 经 `GeneratedImageSaves.saveOnce` 去重，日志为 `[GeneratedSave]`）；图库只放收藏，`LocalGalleryNotifier.favoritesOnly` 始终生效，取消收藏 5 秒后删除文件、期间可撤销，删除历史记录不动图库文件；设置“数据与存储”里的“清理未收藏的图片”删除旧版本存进图库的未收藏文件。生成历史最多 200 条（`GenerationHistoryStorageService.maxEntries`）：每张 PNG 是应用支持目录 `generation_history/` 下的独立文件，Hive 只存顺序与元数据，旧版记录里的字节首次加载时迁移成文件；超出时最旧的记录与文件永久删除，字节经 `GeneratedImageFileCache`（96 MB LRU）按需读取 | 上游修改协调器的重试、保存入口或历史存储时保留这些规则；上游新增保存入口时经 `SystemAlbum.save` 并给出来源标记，不写图库 |
| 后台运行 | 进入后台不再暂停生成队列（`app.dart` 只在 detached 时暂停）；队列从任务运行起持有前台服务，经过 ready 到下一任务都不释放，避免后台重启前台服务被系统拒绝；智能体运行申请前台服务失败时照常运行；智能体等待工具确认时，应用在后台则发通知（与提问共用 `AgentQuestionNotificationService`，确认没有期限）；`GenerationForegroundService.onTimeout` 在 Android 15 的 dataSync 时限到达时停止服务 | 上游修改应用生命周期或队列暂停逻辑时保留后台继续执行；上游改前台服务时保留队列级持有与 `onTimeout` |
| 智能体模型 | ChatGPT（Codex）订阅登录：服务商预设 `chatgptCodex` 与协议 `openaiCodexResponses`，设备码与浏览器登录、令牌刷新、`OpenAiCodexResponsesAdapter`、智能体顶栏额度胶囊；模型目录生成脚本与 lock 加入 `openai-codex`，目录跟随 pi-ai 1.3.0（含 GPT-6），输入框的模型 / 推理强度入口带 Codex 快速模式（`service_tier: priority`，只存本机），生成器按 1.3.0 的规则从各模型档位表推出 Gemini 档位与 Mistral 的 reasoning_effort；Kimi Coding 改为 Chat Completions（`/coding/v1`），旧的默认 Anthropic 配置读取时迁移；详见 [chatgpt_codex.md](chatgpt_codex.md) | 上游新增或修改 `ProviderProtocol` / `ProviderPreset` 的 switch 时补上 Codex 分支；上游重新生成模型目录时保留 `openai-codex` 与其 lock 哈希；上游改 `OpenAiResponsesAdapter` 时保留 `agentEndpoint` 等可覆写钩子 |
| 智能体对话界面 | 工作过程按阶段呈现（`agent_chat_work_process.dart`：阶段性总结为正文、运行中折叠之前阶段的工具、完成后收成阶段总结卡片），同一轮里后发的消息作为引导条目（`AgentChatTurnItem.steer`）显示为“你补充”；输入区底栏为 + / 模型 · 推理 / 权限与联网合一按钮（`AgentChatAccessControl`，设置页不再有权限卡）/ 上下文 / 发送，发送键在运行中按草稿切换停止与“引导当前工作”（`AgentChatSendButton`，长按改为完成后发送），只有触屏且无鼠标时回车换行；用户气泡改为中性色、去掉时间与送达标记，触屏长按出复制/编辑；完全访问只在消耗 Anlas、删除图片、删除或改写库条目时审批（`FullAccessConfirmation`），改写类工具以 `previewChanges` 在审批卡显示差异（`AgentChatChangeDiff` / `diffText`） | 上游修改 `agent_chat_turn.dart` 的工作轨迹时把变化落到 `AgentChatWorkProcess`，不恢复 `AgentChatWorkTrail`；上游修改输入区控件行或发送键时保留合一的权限按钮与引导语义；上游修改 `describeAgentToolPermission` 或新增 `update_` / `delete_` / 收藏类工具时按 `fullAccessConfirmation` 规则归类，库的改写工具补 `previewChanges` |
| 构建 | `scripts/build_android_apk.ps1` 按锁定文件核对工具链；真机迭代参数 `-TargetPlatform android-arm64 -InstallToDevice -FallbackDirectory`（只编 arm64、校验后直接覆盖安装）；依赖指纹忽略 `version:` 行 | 保留；CI 中的包名检查使用新包名 |

## 最近一次移植（2026-10-19）

- 已审阅到上游 `f92ead23`（2026-10-17，4.3.0 之后）。基线仍是最后一次整体合并的 `d1437760`。
- 343 个候选提交按时间顺序逐条处理：直接合入 146、解决冲突后合入 34、部分移植 5；跳过 22（依赖被排除的改造、纯重构或本分支已改写的区域），只改测试且冲突的 23 个保留本分支测试，另有 4 个合入后因依赖暂缓内容而撤回。
- 合入的主要内容：V5 节约 / 标准档位与动漫 / 兽人模式、移除已保存账号、DIY 与随机词库的大批规则修复和窄屏布局、表单标题与页脚的自适应固定、共享输入框清空按钮命中区、智能体按确认请求执行、水印自动选位与自动灰阶、重绘编辑器工具栏与蒙版修复、本地 tagger 缓存与子目录扫描。
- 暂缓（第五批，约 70 个）：元数据读写、哈希、缓存、isolate 与保存命名，以及依赖它们的 EXIF 方向、队列快照异步编码、拖放与导出、对比视图、PixAI tagger、文件名清洗等；之后单独移植。
- 整类排除：桌面键鼠交互、读屏滑块改造（#330 / #346：`NamedSlider`、`LabeledSliderRows`、`LabeledControlRows`、`InputSurfaceDecoration`）、模型服务页（#360）、pi-ai 1.0 目录（本分支已独立升到 1.3.0）、同步到系统相册开关与另存为（与本分支保存模型冲突）、智能体全自动权限与直接放大 / 增强、统计面板删除。依赖这些组件的上游改动按本分支现有组件手动落位：DIY 条件分支与随机词库概率继续用 `SteppedSlider` / `Slider`，概率编辑在窄屏把标签与读数移到滑块上方。
- 保留本分支界面的冲突：手机工作台（返回键逐层退出多选、参数抽屉相关改动不移植）、外观设置的主题模式弹窗、智能体服务商与连接表单的固定标题与页脚、参数面板的分节结构（只吸收“没有高级选项时不显示空分组”）。
- 验证：每步后 `flutter analyze` 无问题；全量测试 1074 个文件分 27 组运行，仅 `skill_archive_service_test` 的 2 个 Windows 符号链接用例失败（环境限制）。

## 移植流程

1. 工作区干净，创建备份分支与本地移植分支；`git fetch upstream`。
2. 列出上次审阅点之后的上游提交，按收益与改动面分为合入、暂缓、排除三类；排除项写明原因。
3. 按时间顺序 `cherry-pick -x`；README 与 CHANGELOG 保留本分支，生成文件取上游后按需重新生成。冲突中的界面部分保留本分支。
4. 每次停下都运行 `flutter analyze`：干净合入的提交也可能引用被跳过或暂缓提交里的符号（如新组件、新文案键、新测试夹具），此时撤回该提交或补上缺失的小文件。
5. 对改到本分支改过的界面文件的提交逐个看 diff，确认没有覆盖本分支设计。
6. 全量测试分组运行；更新本文件，再快进 `android-custom`。

## 已知注意事项

- 4.1.0 起的云备份新格式不能由旧版读取；多设备同步时先全部更新。
- 提示词分组记录暂未加入云同步：记录很小，但需要新增同步类型与四语文案，列为后续项。
- 分组记录按结果图字节哈希匹配；经重新编码的派生图（放大、增强等）不会继承分组，扁平提示词不受影响。
- 320 宽、3 倍字号下，选中文字后的权重工具条会遮住“标签模式”按钮（`text_mode_enabled_actions_test`），待调整工具条避让。
- 触屏“更多操作”菜单在前部加入保存、复用、收藏后，800×600 测试视口中的水印项超出可视范围（`local_image_card_thumbnail_test`），待确认菜单高度约束。
