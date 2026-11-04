# Aaalice Pocket

<p align="center">
  <a href="README.md">简体中文</a> · 繁體中文 · <a href="README.en-US.md">English</a>
</p>

<p align="center">
  <img src="docs/assets/pocket-icon.png" alt="Aaalice Pocket 圖示" width="112">
</p>

<p align="center">
  <strong>裝進口袋的 NovelAI 創作台：專為 Android 手機打磨的 NAI Launcher 分支。</strong>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest"><img src="https://img.shields.io/github/v/release/CSSRS2662/Aaalice_Pocket?include_prereleases&display_name=tag" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/Android-7.0%2B%20arm64-3ddc84?logo=android&logoColor=white" alt="Android 7.0+ arm64">
  <img src="https://img.shields.io/badge/license-MIT-5b8c5a" alt="MIT License">
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher"><img src="https://img.shields.io/badge/上游-NAI%20Launcher-6f7785" alt="上游專案 NAI Launcher"></a>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest">下載最新版</a> ·
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher">上游專案</a> ·
  <a href="#-與上游的關係">與上游的關係</a>
</p>

> Aaalice Pocket 是 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher) 的非官方 Android 分支，由 [CSSRS2662](https://github.com/CSSRS2662) 維護，與上游作者及 NovelAI（Anlatan）均無隸屬或背書關係；名稱中的 “Aaalice” 沿用自上游專案名，用於標明出處。使用線上功能前，請準備自己的 NovelAI 帳號，並遵守相關服務條款、內容規則與當地法律。

## 📱 專注 Android

上游 NAI Launcher 同時面向 Windows、macOS 與 Android。Aaalice Pocket 只做 Android：把手機當作主力創作裝置來設計，單手可及、手勢順手、實機流暢，而不是桌面介面的縮小版。

- **只發布 Android 安裝包。** 桌面端可使用上游 NAI Launcher。
- **獨立套件名稱與簽章。** 套件名稱 `com.cssrs2662.aaalicepocket`，使用本分支自己的簽章，可以和上游版本同時安裝，資料互不影響。
- **獨立發布。** Pocket 使用獨立版本號和發布節奏，按需移植適合 Android 的上游功能與修正。
- **不內建應用內更新。** 新版本請到本儲存庫的 Releases 下載後覆蓋安裝。

## ✨ 為手機重做的部分

| 你會注意到 | Aaalice Pocket 做了什麼 |
| --- | --- |
| **生成工作台** | 頂欄左側放模型與尺寸兩枚膠囊，節約 / 標準檔以主題色儀表盤的中間 / 右側指針表示，切換時平滑轉向，右側額度膠囊上方顯示 Anlas 餘額、下方是以細線分隔的主題色五段體力條，寬度隨左側內容自適應，頂欄無需橫向拖動；下方「圖像 / 提示詞 / 參數 / 參考 / 歷史」頁籤可以左右滑動切換；底欄一行放下抽卡、加入佇列、智慧體、佇列和生成按鈕，進度直接顯示在生成按鈕裡。 |
| **提示詞分區** | 提示詞可以拆成多個分區，以卡片排列：點按編輯（編輯時可用「+」直接新增下一個分區），長按拖曳排序，可以單獨啟用或停用，也能存進詞庫；複用參數時會按原來的分區還原，不會把所有標籤塞進同一個框。 歷史與圖庫的圖片詳情皆依當時啟用的分區和固定詞顯示兩欄卡片，固定詞收起時只顯示名稱與數量；點開可查看並多選複製標籤，點「重用此分區」可只追加該卡片至目前提示詞。 |
| **標籤模式** | 文字與標籤兩種檢視隨時切換，每個標籤下方顯示中文譯文；點按詞條可調整權重、剪下或暫時停用，長按進入多選複製，分區編輯中還可將所選詞條移動到其他可編輯分區；多選時底部顯示操作列，不再彈出權重浮層遮擋選取。 |
| **不靠 AI 的標籤搜尋** | 輸入中文、全拼、自然碼雙拼或首字母都能找到英文標籤，支援同音字與拼字糾錯、把中文短句拆詞比對；另有隨包附帶、完全在本機執行的語意補全。詞庫原本沒有中文的約 840 個常用標籤（如 night_sky、各色 *_footwear）已補上中文名，Danbooru 改過名的舊標籤會直接顯示為新名。 |
| **標籤聯想** | 寫下一個標籤後，按前後已寫的內容推薦接下來的標籤；補全與聯想結果排成緊湊詞塊，翻譯、數量與來源一目了然，標題欄的分類按鈕可以只看一般、角色、作品（打字補全還可選畫師、元資料）；輸入時匹配到提示詞裡已經寫過的標籤，會排在最前面並標出「已寫」；長按詞塊進入多選，可一次插入多個標籤；底欄的「分詞」鍵輸入英文逗號，中文輸入法下不用切換鍵盤。 |
| **詞庫與固定詞** | 詞庫按分組分節排成兩欄，沒有預覽圖的詞條顯示所屬分組的圖示：人物、髮型、場景、風格、構圖等 20 個常用分組自帶圖示，自訂分組用通用圖示。點詞條看詳情，「發送到提示詞」會加在目前提示詞末尾（分組模式下新增一個分區），發送後留在詞庫，可從提示裡直接去生成；長按多選，可一次發送、收藏、移動或新增為固定詞。固定詞排成三欄，點按開關，可按常用（最近兩週用得越多越靠前）、最近使用、自訂或名稱排序；固定詞的分組與詞庫即時一致，在詞庫裡移動詞條，對應的固定詞也會跟著移動。 |
| **局部重繪編輯器** | 畫布佔滿螢幕：頂欄切換「重繪」（改蒙版）與「編輯」（改圖片），工具列只列出目前對象的工具；工具列上方的選項列放最常用的設定，畫布右側的滑桿直接調整筆刷大小，右下角是撤銷與重做；聚焦重繪（Focused Inpaint）改成頂欄下的兩步引導，不再擋住畫面；用手指塗抹時，畫布頂角會出現放大鏡，即時顯示手指擋住的位置和筆觸。 |
| **V5 體力與額度** | 頂欄用五段體力條顯示 Opus 體力，並保留 Anlas 餘額，點開可重新整理餘額、查看準確剩餘量、估算張數和回充速度；張數依目前檔位、尺寸和步數換算（節約檔同樣的體力約可多生成一半），也計入另行購買的額外配額。 |
| **Pocket 主題** | 純白或炭黑的中性底色，搭配 8 種預設強調色或自訂顏色；淺色、深色或跟隨系統。 |
| **流暢度** | 在高刷螢幕上，滑動等觸控操作以螢幕最高更新率執行（如 120Hz，可在「設定 → 外觀 → 高更新率」關閉）；出圖瞬間不再卡頓。 |

## 🎨 完整的 NovelAI 工作流程

Aaalice Pocket 保留了上游在手機上可用的核心能力：

- **生成與編輯**：文生圖、圖生圖、局部重繪、Focused Inpaint、擴圖、變體與增強；支援 NovelAI V5 Curated / Full、V4.5、V4 與 V3 系列，參數會依模型能力自動調整。
- **生成狀態**：單圖的點陣動畫、預覽和成圖共用置中的畫框。下方資訊列始終保留，點種子可以鎖定，再點恢復隨機。停止按鈕顯示批次和進度，可在「設定 → 生成」關閉串流圖像預覽。請求最多在背景重試 5 次，用盡後停止並提示，保留已完成圖片。
- **角色與參考**：多角色分別設定提示詞與位置；Vibe Transfer 與 Precise Reference 有獨立資源庫，可分類、搜尋並直接送入目前任務。
- **固定詞與詞庫**：正負面固定詞、自訂標籤詞庫與隨機詞庫，支援分組、搜尋、常用排序與快速插入。
- **圖庫與歷史**：儲存只存進系統相簿，收藏只存進本機圖庫，所以圖庫裡只有收藏的圖片；取消收藏會把圖片移出圖庫，幾秒內可以撤銷。生成歷史最多保留最近 200 張，超出後最早的一張會被永久刪除。圖庫與歷史都採用瀑布流，圖片選單統一提供儲存、複用參數與收藏，可讀取 NovelAI 圖片中繼資料並選擇性還原；在圖片詳情裡長按某個標籤（或從複製選單選「選擇詞條複製」）可以多選標籤，一次複製選中的幾個。儲存時若系統相簿的 Aaalice NAI Launcher 資料夾裡已有同一張圖（包括舊版本存進去的），本次不儲存並提示，可點「依然儲存」再存一份。舊版本存進圖庫但沒有收藏的圖片，可以在「設定 → 資料與儲存」一鍵清理。
- **分享匯入**：從 Discord 等應用程式把圖片或圖片直鏈分享到 Aaalice Pocket，即可擷取中繼資料、作為圖生圖來源圖或參考圖。
- **線上畫廊**：彙整 Danbooru、Safebooru、Gelbooru、AI TAG 與法典圖鑑，查看原始提示詞並一鍵送回生成頁。
- **佇列與智慧體**：批次任務可以暫停、繼續、排序和重試；智慧體可以幫你查詢標籤、整理提示詞和準備任務，工作過程按階段顯示它在做什麼，中途輸入文字即可引導接下來的工作；完全存取下只有消耗 Anlas、刪除圖片、刪除或改寫庫條目需要你確認，改寫時以差異標出變更；每個對話可以單獨設定只在該對話生效的提示詞。
- **ChatGPT 訂閱登入**：智慧體與提示詞助手可以用 ChatGPT 帳號（Plus、Pro 等）登入，用量計入該帳號的 Codex 額度；智慧體頂欄顯示 5 小時與每週額度的剩餘百分比，點開可看依本機時區換算的重置時間。智慧體可在輸入框的模型與推理強度入口開啟快速模式，約 1.5 倍速度，額度消耗更快。
- **備份與還原**：支援 GitHub 與 WebDAV 雲端備份，推送、拉取與還原都由你主動開始。OneDrive 與 Google Drive 需要建置時提供 OAuth 設定，本分支的發布包未內建。

## 🖼️ 介面預覽

<table>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-generate.png" alt="生成工作台" width="100%"><br>
      <sub>生成工作台：頂欄模型、尺寸與額度</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-streaming.png" alt="串流預覽" width="100%"><br>
      <sub>串流預覽：進度顯示在生成按鈕裡</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-prompt-tags.png" alt="提示詞標籤模式" width="100%"><br>
      <sub>標籤模式：每個標籤附中文譯文</sub>
    </td>
  </tr>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-params.png" alt="參數頁" width="100%"><br>
      <sub>參數頁：尺寸、取樣器與步數</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-appearance.png" alt="外觀設定" width="100%"><br>
      <sub>外觀：強調色與明暗主題</sub>
    </td>
    <td width="33%"></td>
  </tr>
</table>

截圖中的圖像均由 NovelAI V5 Curated 隨機提示詞生成；介面截圖為簡體中文。

## ⚡ 下載與安裝

1. 前往 [Releases](https://github.com/CSSRS2662/Aaalice_Pocket/releases/latest) 下載 `Aaalice_Pocket_<版本>_arm64.apk`，可用同一頁面的 `checksums.txt` 核對 SHA-256。
2. 首次安裝時，依系統提示允許目前應用程式安裝未知來源軟體。
3. 需要 Android 7.0 或更高版本、64 位元 ARM（arm64-v8a）裝置；安裝包內建離線標籤資料庫和語意補全模型，體積約 290MB。
4. 之後升級直接覆蓋安裝即可，資料會保留。本分支與上游使用不同簽章，不能互相覆蓋安裝。

登入可以使用 NovelAI 帳號密碼或 **Persistent API Token**。如果網頁安全驗證導致密碼登入失敗，建議改用 Persistent API Token；Token 只保存在本機安全儲存區中。

## 🔒 資料與隱私

Aaalice Pocket 沒有自己的伺服器，也不收集使用資料。只有在你主動使用對應功能時，資料才會傳送給相關服務：

| 使用的功能 | 資料會傳送到哪裡 |
| --- | --- |
| 生成、圖生圖、重繪、Vibe 編碼 | NovelAI；包括本次請求所需的提示詞、參數和來源圖或參考圖。 |
| 線上畫廊搜尋與下載 | 你選擇的第三方圖庫；可用性、限流和內容規則由各站點決定。 |
| AI 翻譯或智慧體 | 你設定的模型服務；可能產生服務費用。使用 ChatGPT 登入時，請求送往 ChatGPT 的 Codex 服務，登入憑證只保存在本機，不參與雲端同步。 |
| 雲端備份 | 你選擇的 GitHub 或 WebDAV；只上傳明確勾選的內容。 |

- NovelAI Token、GitHub Token 與 WebDAV 密碼保存在裝置安全儲存區中，不會寫入備份。
- 提示詞、圖庫索引、標籤、資源庫和智慧體對話預設只保存在本機；本機圖庫的圖片本體不會上傳。
- 線上畫廊可能包含第三方內容，分級篩選不能取代你自己的判斷。

## 🔗 與上游的關係

- 本分支基於 [Aaalice233/Aaalice_NAI_Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher)，遵循同一份 [MIT License](LICENSE)，保留上游的版權聲明。
- 上游的功能與修正歸功於上游作者和貢獻者；Android 專屬的介面與改動由本分支維護。
- 使用 Aaalice Pocket 時遇到的問題請回報給本分支，不要提交到上游儲存庫。回報前可以在「設定 → 關於 → 匯出診斷日誌」保存排查資訊。
- 想要 Windows、macOS 版本或上游的完整功能，請使用上游的 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher/releases/latest)。

## 🙏 致謝

感謝 [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher) 的作者與全部貢獻者，以及 [NovelAI](https://novelai.net/)、[法典圖鑑](https://novelai.quicktagcloud.com/)、[AgIzT/NovelAI-Tag](https://github.com/AgIzT/NovelAI-Tag)、[ffdkj 中英標籤翻譯表](https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table)、[amenorira/danbooru-tags-data-zh](https://github.com/amenorira/danbooru-tags-data-zh)、[mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data)、[ECDICT](https://github.com/skywind3000/ECDICT)、[multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small)、[Flutter](https://flutter.dev/) 與 [Riverpod](https://riverpod.dev/)。隨包資料與資源的授權資訊見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 📄 授權條款

本專案基於 [MIT License](LICENSE) 開源。NovelAI 及其標誌是 Anlatan 的商標，本專案不主張任何相關權利。
