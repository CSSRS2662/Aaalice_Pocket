# Aaalice Pocket

<p align="center">
  简体中文 · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.en-US.md">English</a>
</p>

<p align="center">
  <img src="docs/assets/pocket-icon.png" alt="Aaalice Pocket 图标" width="112">
</p>

<p align="center">
  <strong>装进口袋的 NovelAI 创作台：专为 Android 手机打磨的 NAI Launcher 分支。</strong>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest"><img src="https://img.shields.io/github/v/release/CSSRS2662/Aaalice_Pocket?include_prereleases&display_name=tag" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/Android-7.0%2B%20arm64-3ddc84?logo=android&logoColor=white" alt="Android 7.0+ arm64">
  <img src="https://img.shields.io/badge/license-MIT-5b8c5a" alt="MIT License">
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher"><img src="https://img.shields.io/badge/上游-NAI%20Launcher-6f7785" alt="上游项目 NAI Launcher"></a>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest">下载最新版</a> ·
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher">上游项目</a> ·
  <a href="#-与上游的关系">与上游的关系</a>
</p>

> Aaalice Pocket 是 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher) 的非官方 Android 分支，由 [CSSRS2662](https://github.com/CSSRS2662) 维护，与上游作者及 NovelAI（Anlatan）均无隶属或背书关系；名称中的 “Aaalice” 沿用自上游项目名，用于标明出处。使用在线功能前，请准备自己的 NovelAI 账号，并遵守相关服务条款、内容规则与当地法律。

## 📱 专注 Android

上游 NAI Launcher 同时面向 Windows、macOS 与 Android。Aaalice Pocket 只做 Android：把手机当作主力创作设备来设计，单手可达、手势顺手、真机流畅，而不是桌面界面的缩小版。

- **只发布 Android 安装包。** 桌面端可使用上游 NAI Launcher。
- **独立包名与签名。** 包名 `com.cssrs2662.aaalicepocket`，使用本分支自己的签名，可以和上游版本同时安装，数据互不影响。
- **独立发布。** Pocket 使用独立版本号和发布节奏，按需移植适合 Android 的上游功能与修复。
- **不内置应用内更新。** 新版本请到本仓库的 Releases 下载后覆盖安装。

## ✨ 为手机重做的部分

| 你会注意到 | Aaalice Pocket 做了什么 |
| --- | --- |
| **生成工作台** | 顶栏左侧放模型与尺寸两枚胶囊，节约 / 标准档以主题色仪表盘的中间 / 右侧指针表示，切换时平滑转向，右侧额度胶囊上方显示 Anlas 余额、下方是以细线分隔的主题色五段体力条，宽度随左侧内容自适应，顶栏无需横向拖动；下方“图像 / 提示词 / 参数 / 参考 / 历史”页签可以左右滑动切换；底栏一行放下抽卡、加入队列、智能体、队列和生成按钮，进度直接显示在生成按钮里。 |
| **提示词分区** | 提示词可以拆成多个分区，以卡片排列：点按编辑（编辑时可用“+”直接新建下一个分区），长按拖动排序，可以单独启用或停用，也能存进词库；复用参数时会按原来的分区恢复，不会把所有标签塞进同一个框。 历史与图库的图片详情均按当时启用的分区和固定词显示两列卡片，固定词收起时只显示名称与数量；点开可查看并多选复制标签，点“复用此分区”可只追加该卡片到当前提示词。 |
| **标签模式** | 文本与标签两种视图随时切换，每个标签下方显示中文译文；点按词条可调整权重、剪切或临时禁用，长按进入多选复制，分区编辑中还可将所选词条移动到其他可编辑分区；多选时底部显示操作条，不再弹出权重浮层遮挡选择。 |
| **不靠 AI 的标签搜索** | 输入中文、全拼、自然码双拼或首字母都能找到英文标签，支持同音字与拼写纠错、把中文短句拆词匹配；另有随包附带、完全在本机运行的语义补全。词库原本没有中文的约 840 个常用标签（如 night_sky、各色 *_footwear）已补上中文名，Danbooru 改过名的旧标签会直接显示为新名。 |
| **标签联想** | 写下一个标签后，按前后已写的内容推荐接下来的标签；补全与联想结果排成紧凑词块，翻译、数量与来源一目了然，标题栏的分类按钮可以只看一般、角色、作品（打字补全还可选画师、元数据）；输入时匹配到提示词里已经写过的标签，会排在最前面并标出“已写”；长按词块进入多选，可一次插入多个标签；底栏的“分词”键输入英文逗号，中文输入法下不用切换键盘。 |
| **词库与固定词** | 词库按分组分节排成两列，没有预览图的词条显示所属分组的图标：人物、发型、场景、风格、构图等 20 个常用分组自带图标，自定义分组用通用图标。点词条看详情，“发送到提示词”会加在当前提示词末尾（分组模式下新增一个分区），发送后留在词库，可从提示里直接去生成；长按多选，可一次发送、收藏、移动或添加为固定词。固定词排成三列，点按开关，可按常用（最近两周用得越多越靠前）、最近使用、自定义或名称排序；固定词的分组与词库实时一致，在词库里移动词条，对应的固定词也会跟着移动。 |
| **局部重绘编辑器** | 画布占满屏幕：顶栏切换“重绘”（改蒙版）与“编辑”（改图片），工具栏只列当前对象的工具；工具栏上方的选项条放最常用的设置，画布右侧的滑杆直接调笔刷大小，右下角是撤销与重做；聚焦重绘（Focused Inpaint）改成顶栏下的两步引导，不再挡住画面；用手指涂抹时，画布顶角会出现放大镜，实时显示手指挡住的位置和笔触。 |
| **V5 体力与额度** | 顶栏用五段体力条显示 Opus 体力，并保留 Anlas 余额，点开可刷新余额、查看准确剩余量、估算张数和回充速度；张数按当前档位、尺寸和步数折算（节约档同样的体力约可多生成一半），也计入另行购买的额外配额。 |
| **Pocket 主题** | 纯白或炭黑的中性底色，搭配 8 种预设强调色或自定义颜色；浅色、深色或跟随系统。 |
| **流畅度** | 在高刷屏上，滑动等触屏操作以屏幕最高刷新率运行（如 120Hz，可在“设置 → 外观 → 高刷新率”关闭）；出图瞬间不再卡顿。 |

## 🎨 完整的 NovelAI 工作流

Aaalice Pocket 保留了上游在手机上可用的核心能力：

- **生成与编辑**：文生图、图生图、局部重绘、Focused Inpaint、扩图、变体与增强；支持 NovelAI V5 Curated / Full、V4.5、V4 与 V3 系列，参数会按模型能力自动调整。
- **生成状态**：单图的点阵动画、预览和成图共用居中的画框。下方信息栏始终保留，点种子可以锁定，再点恢复随机。停止按钮显示批次和进度，可在“设置 → 生成”关闭流式图像预览。请求最多在后台重试 5 次，用尽后停止并提示，保留已完成图片。
- **角色与参考**：多角色分别设置提示词与位置；Vibe Transfer 与 Precise Reference 有独立资源库，可分类、搜索并直接送入当前任务。
- **固定词与词库**：正负面固定词、自定义标签词库与随机词库，支持分组、搜索、常用排序与快速插入。
- **图库与历史**：保存只存进系统相册，收藏只存进本地图库，所以图库里只有收藏的图片；取消收藏会把图片移出图库，几秒内可以撤销。生成历史最多保留最近 200 张，超出后最早的一张会被永久删除。图库与历史都采用瀑布流，图片菜单统一提供保存、复用参数与收藏，可读取 NovelAI 图片元数据并选择性恢复；在图片详情里长按某个标签（或从复制菜单选“选择词条复制”）可以多选标签，一次复制选中的几个。保存时若系统相册的 Aaalice NAI Launcher 文件夹里已有同一张图（包括旧版本存进去的），本次不保存并提示，可点“依然保存”再存一份。旧版本存进图库但没有收藏的图片，可以在“设置 → 数据与存储”一键清理。
- **分享导入**：从 Discord 等应用把图片或图片直链分享到 Aaalice Pocket，即可提取元数据、作为图生图源图或参考图。
- **在线画廊**：聚合 Danbooru、Safebooru、Gelbooru、AI TAG 与法典图鉴，查看原始提示词并一键送回生成页。
- **队列与智能体**：批量任务可以暂停、继续、排序和重试；智能体可以帮你查询标签、整理提示词和准备任务，工作过程按阶段显示它在做什么，中途输入文字即可引导接下来的工作；完全访问下只有消耗 Anlas、删除图片、删除或改写库条目需要你确认，改写时以差异标出改动；每个对话可以单独设置只在该对话生效的提示词。
- **ChatGPT 订阅登录**：智能体和提示词助手可以用 ChatGPT 账号（Plus、Pro 等）登录，用量计入该账号的 Codex 额度；智能体顶栏显示 5 小时和每周额度的剩余百分比，点开可看按本机时区换算的重置时间。智能体可在输入框的模型与推理强度入口开启快速模式，约 1.5 倍速度，额度消耗更快。
- **备份与恢复**：支持 GitHub 与 WebDAV 云备份，推送、拉取与恢复都由你主动开始。OneDrive 与 Google Drive 需要构建时提供 OAuth 配置，本分支的发布包未内置。

## 🖼️ 界面预览

<table>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-generate.png" alt="生成工作台" width="100%"><br>
      <sub>生成工作台：顶栏模型、尺寸与额度</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-streaming.png" alt="流式预览" width="100%"><br>
      <sub>流式预览：进度显示在生成按钮里</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-prompt-tags.png" alt="提示词标签模式" width="100%"><br>
      <sub>标签模式：每个标签附中文译文</sub>
    </td>
  </tr>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-params.png" alt="参数页" width="100%"><br>
      <sub>参数页：尺寸、采样器与步数</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-appearance.png" alt="外观设置" width="100%"><br>
      <sub>外观：强调色与明暗主题</sub>
    </td>
    <td width="33%"></td>
  </tr>
</table>

截图中的图像均由 NovelAI V5 Curated 随机提示词生成。

## ⚡ 下载与安装

1. 前往 [Releases](https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest) 下载 `Aaalice_Pocket_<版本>_arm64.apk`，可用同一页面的 `checksums.txt` 核对 SHA-256。
2. 首次安装时，按系统提示允许当前应用安装未知来源软件。
3. 需要 Android 7.0 或更高版本、64 位 ARM（arm64-v8a）设备；安装包内置离线标签数据库和语义补全模型，体积约 290MB。
4. 以后升级直接覆盖安装即可，数据会保留。本分支与上游使用不同签名，不能互相覆盖安装。

登录可以使用 NovelAI 账号密码或 **Persistent API Token**。如果网页安全验证导致密码登录失败，建议改用 Persistent API Token；Token 只保存在本机安全存储中。

## 🔒 数据与隐私

Aaalice Pocket 没有自己的服务器，也不收集使用数据。只有在你主动使用对应功能时，数据才会发送给相关服务：

| 使用的功能 | 数据会发送到哪里 |
| --- | --- |
| 生成、图生图、重绘、Vibe 编码 | NovelAI；包括本次请求所需的提示词、参数和源图或参考图。 |
| 在线画廊搜索与下载 | 你选择的第三方图库；可用性、限流和内容规则由各站点决定。 |
| AI 翻译或智能体 | 你配置的模型服务；可能产生服务费用。使用 ChatGPT 登录时，请求发往 ChatGPT 的 Codex 服务，登录凭据只保存在本机，不参与云同步。 |
| 云备份 | 你选择的 GitHub 或 WebDAV；只上传明确勾选的内容。 |

- NovelAI Token、GitHub Token 与 WebDAV 密码保存在设备安全存储中，不会写入备份。
- 提示词、图库索引、标签、资源库和智能体会话默认只保存在本机；本地图库的图片本体不会上传。
- 在线画廊可能包含第三方内容，分级筛选不能替代你自己的判断。

## 🔗 与上游的关系

- 本分支基于 [Aaalice233/Aaalice_NAI_Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher)，遵循同一份 [MIT License](LICENSE)，保留上游的版权声明。
- 上游的功能与修复归功于上游作者和贡献者；Android 专属的界面与改动由本分支维护。
- 使用 Aaalice Pocket 时遇到的问题请反馈给本分支，不要提交到上游仓库。反馈前可以在“设置 → 关于 → 导出诊断日志”保存排查信息。
- 想要 Windows、macOS 版本或上游的完整功能，请使用上游的 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher/releases/latest)。

## 🙏 致谢

感谢 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher) 的作者与全部贡献者，以及 [NovelAI](https://novelai.net/)、[法典图鉴](https://novelai.quicktagcloud.com/)、[AgIzT/NovelAI-Tag](https://github.com/AgIzT/NovelAI-Tag)、[ffdkj 中英标签翻译表](https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table)、[amenorira/danbooru-tags-data-zh](https://github.com/amenorira/danbooru-tags-data-zh)、[mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data)、[ECDICT](https://github.com/skywind3000/ECDICT)、[multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small)、[Flutter](https://flutter.dev/) 与 [Riverpod](https://riverpod.dev/)。随包数据与资源的许可信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。NovelAI 及其标志是 Anlatan 的商标，本项目不主张任何相关权利。
