# Tag 检索评测

`golden_queries.json` 有 51 条查询，覆盖字面补全、拼音和自然码、中文错漏字和颠倒、英文低频纠错、无译名标签、口语描述与显式语义冲突。独立冲突集沿用 [E5 的 100 条难例](../semantic_search/semantic_paraphrase_hard_cases.json)，每条同时记录目标标签与冲突标签的排名。

评测读取随包真实目录、AME、Pocket 补充译名、拼音和跨语言词表。开启 E5 时直接调用本地模型和完整向量索引。输出每条的字面、词法、语义和融合排名，也记录目标是否进入候选池，便于区分召回缺失与排序失分。默认用前 20 个可见结果，任一可接受标签进入该窗口即计入 Recall@20。MRR@10 对第一个可接受标签取排名倒数，第 10 名之后计为 0。

## 运行

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run_flutter_tests.ps1 -NoPub -NoTestAssets -Concurrency 1 -TimeoutSeconds 360 -Path 'tool/search_eval/search_eval_test.dart'
```

- `POCKET_SEARCH_EVAL_E5=1` 加入 E5。Windows 系统存在同名 DLL 时，将 `POCKET_SEARCH_EVAL_ORT` 指向项目锁定的 `onnxruntime_v2` 包中的 `windows/onnxruntime.dll`。
- `POCKET_SEARCH_EVAL_DATASET=hard` 运行独立冲突集。
- `POCKET_SEARCH_EVAL_RUN` 指定报告文件名，报告写入 `tool/.tmp/search-eval/`。用不同的 `POCKET_SEARCH_EVAL_INDEX` 名称测冷建，用同一个名称复测热查询。
- 复现旧版时在 `fa35f0566` 的独立检出中运行同一评测文件与数据，设置 `POCKET_SEARCH_EVAL_LEGACY=1` 复现旧版的召回窗口和合并顺序。新版评测使用扩展候选池。

查询耗时从字面检索开始计时，包含词法、可选 E5 推理和重排。计时排除索引构建、E5 初始化、应用的 250 毫秒防抖、可选 ffdkj 词库、网络与界面渲染。RSS 是 Windows 测试进程的总驻留内存，包含 Flutter 测试框架和 E5 运行时。

## 对照结果

2026-11-04 在同一台 Windows 主机串行运行，旧版为 `fa35f0566`。两版使用相同目录、词表与 E5 资源。

| 查询集 | Recall@20 | Top‑5 | MRR@10 |
| --- | ---: | ---: | ---: |
| 51 条主评测，词法与 E5 | 48/51 → 51/51 | 44/51 → 49/51 | 0.735 → 0.870 |
| 51 条主评测，仅词法 | 42/51 → 43/51 | 40/51 → 43/51 | 0.691 → 0.756 |
| 100 条语义难例，词法与 E5 | 39/100 → 50/100 | 27/100 → 40/100 | 0.196 → 0.326 |

语义难例中，目标进入任一来源候选池的次数从 44 增至 54。新版有 46 条的目标未被召回，另有 4 条召回后未进入前 20。标注的冲突标签占据首位的次数从 2 降至 0，进入前五的次数从 15 降至 6。

| Windows 资源指标 | 旧版 | 新版 |
| --- | ---: | ---: |
| 主评测含 E5，热查询 P50 / P95 | 42.8 / 57.8 ms | 43.8 / 68.2 ms |
| 主评测仅词法，热查询 P50 / P95 | 22.5 / 39.3 ms | 22.7 / 35.0 ms |
| 主评测含 E5，峰值进程 RSS | 939.3 MiB | 941.4 MiB |
| 主评测仅词法，峰值进程 RSS | 203.0 MiB | 203.0 MiB |
| 本地词法索引 | 31.8 MiB | 55.6 MiB |
| 后台冷建词法索引 | 11.6 s | 50.7 s |

「双尾马」和「只闭一只眼」原已由 E5 召回，融合后从前 20 外升到首位。「pinze-nez」从候选池缺失变为第 1。「坐在椅子上」对无中文译名的 `sitting_on_chair` 从第 2 升到第 1。「城山」由第 5 降到第 11，「嘴里含着勺子」由第 1 降到第 2。关闭 E5 时，「把衣服敞着穿」仍缺少足够的已知概念，目标未召回。Android 真机延迟与驻留内存尚待实测。
