# Aaalice Pocket

<p align="center">
  <a href="README.md">简体中文</a> · 繁體中文 · <a href="README.en-US.md">English</a>
</p>

<p align="center">
  <img src="docs/assets/pocket-icon.png" alt="Aaalice Pocket 圖示" width="112">
</p>

<p align="center">
  <strong>把 NovelAI 帶著走。Aaalice Pocket 是為 Android 手機設計的 NAI Launcher 分支。</strong>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest"><img src="https://img.shields.io/github/v/release/CSSRS2662/Aaalice_Pocket?display_name=tag" alt="最新正式版"></a>
  <img src="https://img.shields.io/badge/Android-7.0%2B%20arm64-3ddc84?logo=android&logoColor=white" alt="Android 7.0+ arm64">
  <img src="https://img.shields.io/badge/license-MIT-5b8c5a" alt="MIT License">
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher"><img src="https://img.shields.io/badge/上游-NAI%20Launcher-6f7785" alt="上游專案 NAI Launcher"></a>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest">下載最新版</a> ·
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher">上游專案</a> ·
  <a href="#-與上游的關係">與上游的關係</a>
</p>

> Aaalice Pocket 由 [CSSRS2662](https://github.com/CSSRS2662) 維護，是 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher) 的非官方 Android 分支。「Aaalice」沿用原專案的名稱，以標明來源。本專案獨立維護，與上游作者或 NovelAI（Anlatan）沒有隸屬或背書關係。使用線上功能需要自己的 NovelAI 帳號，並請遵守適用的服務條款、內容規範及當地法律。

## 📱 專注 Android

上游 NAI Launcher 支援 Windows、macOS 和 Android。Pocket 專注在手機上的創作流程，讓常用操作用單手就能點到，也能用滑動和長按在各個工具之間切換。

- **提供 Android 安裝檔。** 電腦版請使用上游的 NAI Launcher。
- **獨立的套件名稱與簽章。** Pocket 使用 `com.cssrs2662.aaalicepocket` 和自己的簽章，可與上游版本同時安裝，兩者的資料各自保存。
- **獨立發行。** Pocket 有自己的版本編號和發行時程，也會視需要納入適合 Android 的上游功能與修正。
- **App 內更新。** 從 Pocket 1.0.0 起，正式版會在啟動時檢查更新。你可以在 App 內閱讀更新說明並下載新版。

## ✨ 在手機上怎麼用

| 功能 | 操作方式 |
| --- | --- |
| **生成工作台** | 模型、尺寸和額度集中在畫面上方。切換 V5 Full 的節約或標準模式時，儀表板指針會轉到中間或右側。Anlas 餘額下方的五段體力條採用主題色，寬度會隨左側空間調整。左右滑動可切換「圖像」、「提示詞」、「參數」、「參考」和「歷史」分頁。抽卡、加入佇列、智慧體和佇列都在下方，張數和進度直接顯示在生成按鈕上。 |
| **提示詞分區** | 把提示詞拆成卡片後，可以點一下編輯、長按拖曳排序，或個別啟用、停用及存到詞庫。編輯時按「+」就能新增一區。圖片留有分區紀錄時，從歷史或圖庫開啟圖片詳情，就會看到當時啟用的分區和固定詞，以雙欄卡片呈現。固定詞收合時只顯示名稱和數量。展開後可複製多個標籤，也能單獨把整個分區加到目前的提示詞。沿用整張圖的參數時，會一併還原原本的分區。 |
| **標籤模式** | 可在文字和標籤兩種檢視之間切換。有中文譯名的標籤會附上翻譯。點一下標籤可調整權重、剪下或暫時停用。長按可多選複製，也能在編輯分區時移到其他可編輯的分區。多選的操作集中在下方工具列。 |
| **離線標籤搜尋** | 支援中文、英文、完整拼音、自然碼雙拼和拼音首字母。也能比對中文少字、打錯字或相鄰字對調的查詢，並提供英文拼字修正。還沒翻譯的英文標籤也能用中文概念搜尋，再和本機的 E5 語意建議一起排序。已補上約 840 個常用標籤的中文名稱。Danbooru 已改名的標籤會顯示新名稱。 |
| **標籤聯想** | 輸入標籤後，App 會依前後的提示詞推薦接下來可用的標籤。建議會標出譯名、數量和來源，可依一般、角色或作品篩選，輸入時的自動完成還能篩選繪師和中繼資料。已經寫過的相符標籤會排在前面並加上「已寫」標記。長按可一次選取並插入多個標籤。用中文輸入法時，按下方的「分詞」即可輸入半形逗號。 |
| **詞庫與固定詞** | 詞庫依群組排成兩欄。沒有預覽圖的項目會以群組圖示代替，人物、髮型、場景、風格和構圖等 20 個常用群組各有圖示，自訂群組則使用通用圖示。點一下可看詳細內容，也可把詞條加到目前的提示詞末尾。分組模式下會新增一個分區，原本的詞庫項目也會保留。長按可多選並批次傳送、收藏、移動或加為固定詞。固定詞排成三欄，點一下即可切換，可依近兩週的使用頻率、最近使用、自訂順序或名稱排序。詞庫項目移到其他群組時，對應的固定詞也會跟著移動。 |
| **局部重繪編輯器** | 全螢幕畫布上方可切換「重繪」與「編輯」，分別調整遮罩和圖片。工具列會依模式顯示可用工具，上方集中常用設定。拖曳畫布右側的滑桿可調整筆刷，右下角提供復原和重做。聚焦重繪（Focused Inpaint）的兩步操作提示在畫面上方。用手指塗抹時，角落的放大鏡會顯示手指下方的筆觸。 |
| **V5 體力與額度** | 上方的五段體力條顯示 Opus 體力，旁邊也能看到 Anlas 餘額。點開可重新整理餘額、查看剩餘體力和恢復速度，或估算還能生成幾張圖。張數依模式、尺寸和步數計算，也會納入另外購買的額度。 |
| **Pocket 主題** | 可選淺色、深色或跟隨系統，以白色或炭黑色為底，搭配 8 種預設強調色，也可自訂顏色。 |
| **高更新率** | 支援高更新率的螢幕可讓滑動和觸控操作跟上裝置的更新率，例如 120 Hz。可在「設定 → 外觀」關閉高更新率。 |

## 🎨 完整的 NovelAI 工作流程

Aaalice Pocket 保留了上游在手機上可用的主要功能。

- **生成與編輯**。支援文字生圖、以圖生圖、局部重繪、聚焦重繪、擴圖、變體和影像增強。可使用 NovelAI V5 Curated／Full、V4.5、V4 和 V3 系列，App 會依模型支援的功能調整參數。
- **生成進度**。單張圖的點陣動畫、串流預覽和完成圖共用置中的畫框，下方會保留圖片資訊列。點一下種子值即可鎖定，再點一次就回到隨機。停止按鈕會顯示目前張數和進度。可在「設定 → 生成」關閉「顯示串流圖像預覽」。遇到可重試的錯誤時，App 會在背景最多重試 5 次，仍失敗就停止這批生成並顯示提示。已完成的圖片會保留。
- **角色與參考圖**。可分別設定每個角色的提示詞和位置。Vibe Transfer 和 Precise Reference 各有獨立資料庫，可分類、搜尋，再直接加到手上的生成工作。
- **固定詞與詞庫**。正向和負向固定詞、自訂標籤詞庫和隨機詞庫，都可分組、搜尋、依使用頻率排序，也能快速加入提示詞。
- **圖庫與歷史紀錄**。按「儲存」會把圖存到手機相簿，按「收藏」則會把圖收進 Pocket 的本機圖庫。取消收藏後，有幾秒可以復原。生成歷史會保留最近 200 張，超過上限時會刪除最舊的一張。兩處皆可用瀑布流瀏覽，從圖片選單儲存、收藏或沿用參數，也可讀取 NovelAI 的圖片中繼資料並選擇要還原的內容。在圖片詳情中長按標籤，或從複製選單選「選擇詞條複製」，即可一次複製多個標籤。若手機相簿的 Aaalice NAI Launcher 資料夾已有相同圖片，App 會先詢問是否要再存一份。舊版留在圖庫的未收藏圖片可從「設定 → 資料與儲存」清理。
- **同詞瀏覽**。在本機圖庫的「日期」和「分類」旁點「同詞」，正向、負向與角色提示詞完全相同的收藏圖會合為一組。群組以瀑布流呈現，近期生成紀錄裡最新的同詞圖會優先當封面，也會把對應的群組往前排。點卡片可在獨立視窗瀏覽組內收藏。下次開啟 App 時會回到上次使用的圖庫檢視。
- **分享後匯入**。從 Discord 或其他 App 將圖片或圖片的直接連結分享到 Aaalice Pocket，就能讀取中繼資料，或將圖片作為以圖生圖的來源或參考。
- **線上畫廊**。可瀏覽 Danbooru、Safebooru、Gelbooru、AI TAG 和法典圖鑑，查看原始提示詞，並直接帶回生成頁使用。
- **佇列與智慧體**。批次工作可暫停、繼續、調整順序或重試。智慧體可以幫你查標籤、整理提示詞和準備生成工作。執行中會顯示各階段的進度，也能隨時補充指示。在完全存取模式下，消耗 Anlas、刪除圖片，以及刪除或改寫詞庫項目時仍會請你確認。改寫前可先看差異。每段對話都可以設定專用提示詞。從更多選單選擇「清除對話脈絡」，或輸入 /clear，就能保留提示詞並重新開始聊天。
- **使用 ChatGPT 訂閱帳號登入**。智慧體和提示詞助理可用 ChatGPT 帳號（如 Plus 或 Pro）登入，用量計入該帳號的 Codex 額度。智慧體上方可查看 5 小時及每週剩餘額度，點開可查看依本機時區顯示的重設時間。可從輸入框的模型與推理強度選單開啟快速模式，速度約為平常的 1.5 倍，額度也會用得更快。
- **備份與還原**。可用 GitHub 或 WebDAV 備份到雲端，上傳、下載與還原都由你手動開始。OneDrive 和 Google Drive 需要在建置時提供 OAuth 設定，目前的正式安裝檔未附這兩項設定。

## 🖼️ 介面預覽

<table>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-generate.png" alt="生成工作台" width="100%"><br>
      <sub>在生成頁上方切換模型、選擇尺寸及查看額度</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-streaming.png" alt="串流預覽" width="100%"><br>
      <sub>串流預覽，生成按鈕上也能看到進度</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-prompt-tags.png" alt="提示詞標籤模式" width="100%"><br>
      <sub>標籤模式可直接查看中文譯名</sub>
    </td>
  </tr>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-params.png" alt="參數頁" width="100%"><br>
      <sub>在參數頁調整尺寸、取樣器和步數</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-appearance.png" alt="外觀設定" width="100%"><br>
      <sub>在外觀設定選擇強調色及淺色或深色主題</sub>
    </td>
    <td width="33%"></td>
  </tr>
</table>

截圖裡的圖片是用 NovelAI V5 Curated 搭配隨機提示詞生成的。畫面以簡體中文介面示範。

## ⚡ 下載、安裝與更新

- **第一次安裝，或從舊版 Pocket 升級**。到 [GitHub Releases](https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest) 下載 `Aaalice_Pocket_<版本>_arm64.apk`，可用同頁的 `checksums.txt` 核對 SHA-256。請使用搭載 Android 7.0 以上的 64 位元 ARM（arm64-v8a）裝置。APK 約 290 MiB，內含離線標籤資料庫和語意建議模型。若 Android 出現提示，請允許開啟 APK 的 App 安裝未知來源的應用程式。
- **Pocket 1.0.0 以上的正式版**。從啟動畫面開啟 Pocket 時，App 會向 GitHub Releases 檢查更新。有新版時，點一下下方的通知即可閱讀更新說明，接著選「一鍵更新」或「前往專案頁面」。APK 下載並驗證完成後，請在 Android 安裝畫面確認更新。你也可以到「設定 → 關於」手動檢查，或從 Releases 下載。
- **保留原有資料**。更新時直接安裝相同簽章的 Pocket，就能保留 App 內的資料。Pocket 與上游 NAI Launcher 可以同時安裝。

可用 NovelAI 帳號密碼或 **Persistent API Token** 登入。如果網頁安全驗證擋住密碼登入，可改用 Persistent API Token。Token 只會儲存在這台裝置的安全儲存空間。

## 🔒 資料與隱私

Aaalice Pocket 沒有自營伺服器，也不蒐集使用情形。以下功能會連線到對應的第三方服務。

| 使用的功能 | 資料會傳送到哪裡 |
| --- | --- |
| 生成、以圖生圖、重繪和 Vibe 編碼 | NovelAI 會收到該次請求需要的提示詞、參數，以及來源圖或參考圖。 |
| 版本檢查與下載更新 | App 啟動時會讀取 GitHub Releases 的公開發行資訊。下載更新不必登入 GitHub。 |
| 線上標籤建議 | 啟用線上查詢時，目前的搜尋詞或用來聯想的標籤會傳給預設服務。可在「設定 → 資料與儲存 → 資料來源與快取」選擇 Danbooru 或 AIBooru。開啟備用來源後，只有首選服務失敗且沒有可用建議時，才會改查另一個來源。 |
| 線上畫廊搜尋與下載 | 你選擇的第三方圖庫。服務是否可用、請求次數限制和內容規範依各網站而定。 |
| AI 翻譯或智慧體 | 你設定的模型服務，可能另行收費。以 ChatGPT 帳號登入時，請求會送到 ChatGPT 的 Codex 服務，登入憑證只保留在這台裝置，也不會同步到雲端。 |
| 雲端備份 | 你選擇的 GitHub 或 WebDAV 服務，只上傳你勾選的內容。 |

- NovelAI Token、GitHub Token 和 WebDAV 密碼會存放在裝置的安全儲存空間，不會包含在備份裡。
- 提示詞、圖庫索引、標籤、資料庫和智慧體對話預設只存在本機。雲端備份不會上傳本機圖庫的圖片檔案。
- 線上畫廊可能顯示第三方內容，仍請自行判斷內容是否適合。

## 🔗 與上游的關係

- Pocket 源自 [Aaalice233/Aaalice_NAI_Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher)，同樣採用 [MIT 授權](LICENSE)，並保留原專案的著作權聲明。
- 感謝上游作者與貢獻者提供的功能和修正。Pocket 的手機介面與專屬改動由本專案維護。
- 使用 Pocket 遇到問題時，請到 [Pocket 的 GitHub Issues](https://github.com/CSSRS2662/Aaalice_Pocket/issues) 回報。可先到「設定 → 關於 → 匯出診斷日誌」，儲存有助於釐清問題的資料。
- Windows、macOS 版與上游的完整功能，可到 [NAI Launcher 的發行頁](https://github.com/Aaalice233/Aaalice_NAI_Launcher/releases/latest) 下載使用。

## 🙏 致謝

感謝 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher) 的作者與所有貢獻者，也感謝 [NovelAI](https://novelai.net/)、[法典圖鑑](https://novelai.quicktagcloud.com/)、[AgIzT/NovelAI-Tag](https://github.com/AgIzT/NovelAI-Tag)、[ffdkj 中英標籤翻譯表](https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table)、[amenorira/danbooru-tags-data-zh](https://github.com/amenorira/danbooru-tags-data-zh)、[mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data)、[ECDICT](https://github.com/skywind3000/ECDICT)、[multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small)、[Flutter](https://flutter.dev/) 和 [Riverpod](https://riverpod.dev/)。安裝檔所附資料和資源的授權資訊，請見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 📄 授權條款

本專案以 [MIT 授權](LICENSE) 開放原始碼。NovelAI 及其標誌為 Anlatan 的商標。
