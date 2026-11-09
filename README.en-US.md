# Aaalice Pocket

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · English
</p>

<p align="center">
  <img src="docs/assets/pocket-icon.png" alt="Aaalice Pocket icon" width="112">
</p>

<p align="center">
  <strong>A NovelAI studio that fits in your pocket: an Android-only branch of NAI Launcher, tuned for phones.</strong>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest"><img src="https://img.shields.io/github/v/release/CSSRS2662/Aaalice_Pocket?display_name=tag" alt="Latest stable release"></a>
  <img src="https://img.shields.io/badge/Android-7.0%2B%20arm64-3ddc84?logo=android&logoColor=white" alt="Android 7.0+ arm64">
  <img src="https://img.shields.io/badge/license-MIT-5b8c5a" alt="MIT License">
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher"><img src="https://img.shields.io/badge/upstream-NAI%20Launcher-6f7785" alt="Upstream project NAI Launcher"></a>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest">Download</a> ·
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher">Upstream project</a> ·
  <a href="#-relationship-to-upstream">Relationship to upstream</a>
</p>

> Aaalice Pocket is an unofficial Android branch of [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher), maintained by [CSSRS2662](https://github.com/CSSRS2662). It is not affiliated with or endorsed by the upstream author or by NovelAI (Anlatan); "Aaalice" in the name comes from the upstream project name to show where it comes from. Online features need your own NovelAI account; follow the applicable terms of service, content rules, and local laws.

## 📱 Android only

Upstream NAI Launcher targets Windows, macOS, and Android. Aaalice Pocket targets Android alone. It treats the phone as the main creative device: reachable with one hand, natural to drive with gestures, smooth on real hardware, rather than a shrunken desktop layout.

- **Android packages only.** For desktop builds, use upstream NAI Launcher.
- **Own package name and signature.** The package is `com.cssrs2662.aaalicepocket`, signed with this branch's own key. It installs side by side with upstream builds and keeps its data separate.
- **Independent releases.** Pocket uses its own versioning and release schedule, selectively porting upstream features and fixes that fit Android.
- **In-app updates.** Starting with Pocket 1.0.0, stable builds check for updates at startup and let you read the release notes and download updates in the app.

## ✨ Reworked for phones

| What you'll notice | What Aaalice Pocket does |
| --- | --- |
| **Generation workbench** | The top bar places model and size pills on the left, with a theme-colored gauge whose needle moves between Medium and High effort. The quota pill on the right shows the Anlas balance above a stamina bar in the theme color with five segments separated by thin lines; its width adapts to the left controls, keeping the top bar free of horizontal scrolling. The Image / Prompt / Parameters / References / History tabs below switch with a horizontal swipe. One bottom row holds the gacha toggle, add to queue, agent, queue, and the Generate button, which shows progress inside itself. |
| **Prompt sections** | Split a prompt into sections shown as cards: tap to edit (the + key there adds the next section right away), long-press and drag to reorder, enable or disable each one, or save it to the library. Reusing parameters restores the original sections instead of putting every tag into one box. When section records are available, history and gallery image details show expandable cards in two columns for the sections and fixed tags used for that image. Collapsed fixed-tag cards show only the name and count. Tags retain multi-select copying, and "Reuse this section" appends just that card to the current prompt. |
| **Tag mode** | Switch between text and tag views at any time; tags show Chinese translations when available. Tap a tag to adjust its weight, cut it, or temporarily disable it. Long-press to select several tags for copying, or move them to another editable section in the section editor. Selection actions stay below the tags without an overlapping weight toolbar. |
| **Offline tag search** | Find English tags using Chinese, full pinyin, Natural Code double pinyin, or pinyin initials. Search handles homophones, some typos, and short Chinese phrases split into words. The built-in E5 semantic suggestions run on the device. Around 840 commonly used tags gained Chinese translations. Renamed Danbooru tags show their new names. |
| **Tag suggestions** | After you write a tag, the app suggests what to write next from the tags around it. Completions and suggestions are laid out as compact blocks that show the translation, count, and sources at a glance, and the category buttons in the header narrow them to general tags, characters, or series (typed completions also to artists and meta tags). A tag that your prompt already has comes first when your typing matches it, marked as already written. Long-press a block to pick several and insert them at once. A “split” key in the toolbar types the comma, so a Chinese keyboard never has to be switched away. |
| **Tag library and fixed tags** | The library shows entries in two columns, sectioned by group; entries without a preview image show their group's icon. Twenty common groups such as character, hair, scene, style, and composition come with their own icons, and custom groups use a general one. Tap an entry for its details; "Send to prompt" adds it after the current prompt (as a new section in sectioned mode) and keeps you in the library, with a shortcut to generate in the notice. Long-press to select several entries and send, favorite, move, or add them as fixed tags at once. Fixed tags sit in three columns: tap to switch one on or off, and sort by frequent use (more uses in the last two weeks come first), recent use, your own order, or name. Fixed tags follow the library's groups in real time, so moving an entry in the library moves its fixed tag too. |
| **Inpaint editor** | The canvas fills the screen. The top bar switches between Inpaint (edits the mask) and Edit (edits the image), and the tool bar lists only that target's tools. The strip above it holds the most-used settings, a slider on the right of the canvas sets the brush size, and undo and redo sit in the bottom-right corner. Focused Inpaint is now a two-step guide under the top bar instead of a card over the image. While you paint with a finger, a loupe in a top corner of the canvas shows the spot and the stroke under your finger. |
| **V5 stamina and balance** | The top bar shows Opus stamina as a five-segment bar alongside the Anlas balance; tap it to refresh the balance and see the exact remaining amount, estimated images, and refill rate. The image count follows the current effort, size, and steps and includes any extra usage you bought. |
| **Pocket theme** | Neutral white or charcoal backgrounds with 8 preset accent colors or a custom one; light, dark, or follow the system. |
| **High refresh rate** | Supported screens can use higher refresh rates, such as 120 Hz. Turn it off in Settings → Appearance. |

## 🎨 The full NovelAI workflow

Aaalice Pocket keeps the upstream capabilities that work on phones:

- **Generation and editing**: text-to-image, image-to-image, inpainting, Focused Inpaint, outpainting, variations, and enhancement. Supports NovelAI V5 Curated / Full, V4.5, V4, and V3, with parameters adjusted to each model's capabilities.
- **Generation status**: for single images, the loading dots, preview, and final image share a centered frame. The info bar stays visible below it. Tap the seed to lock it, then tap again to restore random generation. The stop button shows the batch count and progress. Turn off streaming image previews in Settings → Generation. Retryable generation errors trigger up to five retries in the background, then stop with an error and keep completed images.
- **Characters and references**: per-character prompts and positions. Vibe Transfer and Precise Reference have their own libraries for sorting, searching, and sending straight into the current task.
- **Fixed tags and libraries**: positive and negative fixed tags, a custom tag library, and random tag libraries, with groups, search, frequency sorting, and quick insertion.
- **Gallery and history**: saving puts an image in your photo gallery and favoriting puts it in the local gallery, so the local gallery holds favorites only; unfavoriting removes an image from it, with a few seconds to undo. Generation history keeps the latest 200 images, and the oldest one is permanently deleted when a new one arrives. Both use a masonry layout. Every image menu offers save, reuse parameters, and favorite, and NovelAI image metadata can be read and selectively restored. In the image details, long-press a tag (or choose Pick tags to copy from the copy menu) to pick several tags and copy just those. If the Aaalice NAI Launcher folder of your photo gallery already has the image you are saving, including copies saved by earlier versions, it isn't saved again; the notice offers Save anyway to keep a second copy. Images that earlier versions put in the gallery without a favorite can be cleaned up in one tap under Settings → Data & Storage.
- **Share to import**: share an image or a direct image link from Discord or other apps to Aaalice Pocket to extract metadata or use it as an img2img source or reference.
- **Online galleries**: Danbooru, Safebooru, Gelbooru, AI TAG, and the QuickTagCloud codex, with original prompts you can send back to the generation page.
- **Queue and agent**: pause, resume, reorder, and retry batch tasks. The agent can look up tags, tidy prompts, and prepare tasks; its work shows stage by stage, and typing while it works guides what it does next. With full access it only asks before spending Anlas, deleting images, or deleting or rewriting library entries, and rewrites show the changes as a diff. Each conversation can have its own instructions that apply to it alone.
- **ChatGPT subscription sign-in**: the agent and the prompt assistant can sign in with a ChatGPT account (Plus, Pro and others); usage counts toward that account's Codex limits. The agent header shows how much of the 5-hour and weekly limits is left, and tapping it shows the reset times in your device's time zone. The agent can switch on Fast mode from the model and reasoning control in the input box: about 1.5x speed, using the limits faster.
- **Backup and restore**: cloud backup to GitHub and WebDAV; you start every push, pull, and restore. OneDrive and Google Drive need OAuth settings at build time, which this branch's release packages do not include.

## 🖼️ Screenshots

<table>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-generate.png" alt="Generation workbench" width="100%"><br>
      <sub>Workbench: model, size, and balance in the top bar</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-streaming.png" alt="Streaming preview" width="100%"><br>
      <sub>Streaming preview with progress in the Generate button</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-prompt-tags.png" alt="Prompt tag mode" width="100%"><br>
      <sub>Tag mode with Chinese translations</sub>
    </td>
  </tr>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-params.png" alt="Parameters" width="100%"><br>
      <sub>Parameters: size, sampler, and steps</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-appearance.png" alt="Appearance settings" width="100%"><br>
      <sub>Appearance: accent color and theme</sub>
    </td>
    <td width="33%"></td>
  </tr>
</table>

All images in the screenshots were generated with NovelAI V5 Curated from random prompts; the UI is shown in Simplified Chinese.

## ⚡ Download, install, and update

- **First install or upgrade from an older Pocket build.** Download `Aaalice_Pocket_<version>_arm64.apk` from [GitHub Releases](https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest). You can verify its SHA-256 using `checksums.txt` on the same page. It requires Android 7.0 or later on a 64-bit ARM (arm64-v8a) device. The APK is about 290 MiB and includes the offline tag database and semantic completion model. If prompted, allow the app opening the APK to install unknown apps.
- **Pocket 1.0.0 and later stable releases.** Pocket checks GitHub Releases when it starts. Tap the notice at the bottom to read the release notes, then choose Update now or Go to project page. Once Pocket downloads and verifies the APK, confirm the update in Android's installer. You can also check from Settings → About or download from Releases.
- **Keeping your data.** Install the update over a Pocket build with the same signature to keep your app data. Pocket and upstream NAI Launcher can be installed side by side.

Sign in with your NovelAI email and password or a **Persistent API Token**. If the website's security check makes password sign-in fail, use a Persistent API Token instead; it is kept only in the device's secure storage.

## 🔒 Data and privacy

Aaalice Pocket has no server of its own and collects no usage data. These features connect to third-party services.

| Feature | Where data goes |
| --- | --- |
| Generation, img2img, inpainting, Vibe encoding | NovelAI, including the prompt, parameters, and source or reference images the request needs. |
| Update checks and downloads | GitHub Releases. Startup checks read public release information, and downloads require no GitHub account. |
| Online tag suggestions | Search terms go to Danbooru when the online source is enabled and a query is sent. |
| Online gallery search and downloads | The third-party gallery you choose; each site sets its own availability, rate limits, and content rules. |
| AI translation or the agent | The model service you configure, which may charge fees. With ChatGPT sign-in, requests go to ChatGPT's Codex service; the sign-in tokens stay on this device and are not synced. |
| Cloud backup | The GitHub or WebDAV target you choose; only the items you select are uploaded. |

- Your NovelAI token, GitHub token, and WebDAV password stay in the device's secure storage and are never written to backups.
- Prompts, the gallery index, tags, libraries, and agent sessions stay on the device by default; cloud backups exclude local gallery image files.
- Online galleries may contain third-party content, and rating filters do not replace your own judgment.

## 🔗 Relationship to upstream

- This branch is based on [Aaalice233/Aaalice_NAI_Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher), uses the same [MIT License](LICENSE), and keeps the upstream copyright notice.
- Credit for upstream features and fixes goes to the upstream author and contributors; this branch maintains the Android-specific interface and changes.
- Report problems with Pocket in [Pocket's GitHub Issues](https://github.com/CSSRS2662/Aaalice_Pocket/issues). Before reporting, you can save troubleshooting data with Settings → About → Export diagnostic logs.
- For Windows or macOS builds, or upstream's full feature set, use upstream [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher/releases/latest).

## 🙏 Acknowledgements

Thanks to the author and all contributors of [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher), and to [NovelAI](https://novelai.net/), [QuickTagCloud](https://novelai.quicktagcloud.com/), [AgIzT/NovelAI-Tag](https://github.com/AgIzT/NovelAI-Tag), the [ffdkj Chinese-English tag table](https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table), [amenorira/danbooru-tags-data-zh](https://github.com/amenorira/danbooru-tags-data-zh), [mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data), [ECDICT](https://github.com/skywind3000/ECDICT), [multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small), [Flutter](https://flutter.dev/), and [Riverpod](https://riverpod.dev/). License details for bundled data and assets are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 📄 License

This project is open source under the [MIT License](LICENSE). NovelAI and its logo are trademarks of Anlatan; this project claims no rights to them.
