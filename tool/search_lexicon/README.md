# 非 AI 搜索词表

`assets/search_lexicon/` 中的两个文件由本目录的脚本生成，供补全的拼音、拆词匹配使用：

| 文件 | 内容 | 来源 |
| --- | --- | --- |
| `hanzi_pinyin.json.gz` | 每个汉字至多 3 个无声调读音，常用读音在前（ü 写作 v） | [mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data)（MIT）：先取 `kMandarin`，再补 `kTGHZ2013` |
| `zh_en_lexicon.json.gz` | 中文词 → 至多 4 个英文 tag 词；以及拆词时丢弃的虚词 | `zh_en_overrides.json` 人工词表 > AME 中文词库中的单词通用 tag > [ECDICT](https://github.com/skywind3000/ECDICT)（MIT）释义；词形取自 ECDICT `exchange`，只保留在 tag 名中出现过的词 |

`manifest.json` 记录来源提交、各文件大小与 SHA-256，`test/core/autocomplete/lexical/search_lexicon_test.dart` 校验二者一致。两份 MIT 许可证随包放在同一目录。DSO 等 GPL 数据不得使用。

## 重新生成

来源文件按 `source_lock.json` 固定的提交、大小和 SHA-256 下载到 `tool/.tmp/search-lexicon/source/`，校验不符时脚本失败：

```powershell
tool/.tmp/semantic-search/venv/Scripts/python.exe tool/search_lexicon/build_search_lexicon.py --fetch
tool/.tmp/semantic-search/venv/Scripts/python.exe tool/search_lexicon/build_search_lexicon.py
```

脚本同时读取 `assets/databases/tag_catalog.db`（统计 tag 词频）和 `assets/zh_lexicon/ame_lexicon.json.gz`，二者变化后应重新生成。修改 `zh_en_overrides.json` 后重新生成并提交两份数据与清单。

## 设备上的索引

应用在后台用随包目录、AME、Pocket 补充译名和已安装的 ffdkj 词库构建设备本地索引 `autocomplete/lexical_index.db`。索引包含精确与折叠拼音、单字与相邻字对、英文词表及其拼写删除签名。一般类 Tag 的英文名称、别名、词干与可拆分的合成词组成独立的概念索引。概念匹配只参与召回与排序，译文仍由共享翻译解析器提供。数据指纹或索引版本变更时自动重建缓存，缓存仅保存在本机。

## 评测

评测入口和指标见 [Tag 检索评测](../search_eval/README.md)。
