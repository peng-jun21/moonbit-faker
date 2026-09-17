# 验证与复现

以下为 0.4.0 在本机实际执行的范围；不是全量 Faker 符合性声明。Node 24.11.0、Python 3.14.4、Moon 0.1.20260904 / moonc 0.10.12、Windows、Intel i7-14700HX。没有远程 CI、发布或上传。

## 日常离线检查

```powershell
./verify.ps1 -MoonPath C:/path/to/moon/bin/moon.exe
```

执行 fmt/info、deny-warn check、JS/Wasm-GC 两目标、实际 JS 引擎重建、原示例和文件/stdin CLI、独立格式检查、官方捕获输出回放、新 Worker/stream CLI、307 条有种子的异常输入及原示例计时。CI 配置也包含这些入口，但远程尚未运行。

- JS 与 Wasm-GC **各 22 组**：原有 16 组保留，新增 5 组会话/结构/所有权/失败回滚/地区测试及 1 组含 651 个官方向量的测试。组数不是 provider 覆盖率。
- 原 256 行 × 26 列的 JSON/JSONL/CSV 由 Python json/csv/uuid/ipaddress/datetime/decimal 等独立检查；10 类坏配置、实际 schema 文件和空 JSONL CLI 通过。
- `node tools/check-locales.mjs` 用当前编译引擎回放 651 组捕获的官方输出，覆盖全部 217 个公开地区/方法组合，合计 5208 个值。
- `node tools/test-stream.mjs` **9 组**：不同批边界/恢复逐字节一致、1100 行关联表、特殊表名、异步消费者背压、取消/超时/写失败清理、行失败与并发操作拒绝、独立 CSV 解析、实际 CLI 分段恢复/损坏拒绝、防覆盖/严格 UTF-8/字节限制/临时文件清理，以及十万行流式。
- 十万行顺序和唯一集合逐条检查，5006048 字节输出 SHA256 为 `9e6e6894ed0685dd06ea7ff471a2996f8f1d59075822bdab686b54d828d7fe98`。最后一次约 1594ms，采样进程 RSS 148643840 字节；包括 Worker、JSON、检查与检查点。这不是精确峰值，也不是官方吞吐对照。
- 地区导出、黄金向量生成、moon fmt/info 连续两轮后 24 份源码/API/数据/许可证字节未变化。

完整 verify 后只改了 Node 多表缓存对特殊表名的处理，相关 9 组已重跑通过；核心和生成引擎未再次改变。原格式记录使用 `structured-record-generation.json`、`structured-python-validation.json` 保存本轮版本，旧 provider-upgrade 等证据保留历史含义。例行脚本可能刷新运行时证据日期；最终提交以 structured-upgrade 清单为准。

## 官方词库与独立输出

固定 [Faker 40.39.0 官方 wheel](https://pypi.org/project/Faker/40.39.0/)，SHA256 为 `c4c7ec2cddfaf602c5a8a2c960614946aa8c161250bd9d49a8846cd24d1ef028`。生产代码不导入 Python Faker。参考目录必须位于本仓库之外；Windows 参考环境须有 Faker 所需的 tzdata，wheel 未复制任何可选图像依赖。

```powershell
python tools/fetch-reference.py C:/scratch/faker-reference
python tools/export-locales.py C:/scratch/faker-reference/site
node tools/compare-locales.mjs C:/scratch/faker-reference/site
python tools/generate-locale-goldens.py
moon fmt
moon info
```

导出六地区的选定 provider 实际词库、权重和模板，遵循官方 provider 回退。225 表中有 8 张英国邮编内部表，公开目录为 217 个地区/方法组合，28847 条含重复条目。原官方源码保持不变；`data/provenance.json` 包含读取的源码 SHA256、wheel 与数据 hash，MIT 许可随库保留。

独立参考由官方 Faker provider 执行。为隔离词库/格式行为，参考明确使用 `reference-locales.py` 的 xorshift32 Random 适配器（random、randrange、choice、randint）；不使用 Faker 默认 MT19937。217 组合 × 3 种子（1、42、987654321）× 8 值，651/651 案例、5208/5208 值一致，保存双方原结果。黄金测试从 reference.values 生成，不能用本地 actual 字段替代。

可复现的相同 seed 输出只适用于同版本、同配置、同调用顺序。未主张跨 Faker 版本、默认 RNG 或全部参数序列兼容。

## 分布检查

```powershell
node tools/test-statistics.mjs
python tools/validate-statistics.py C:/scratch/faker-reference/site
```

固定预设种子 198703、100000 行；20 桶均匀整数 χ²=11.6052（阈值 43.83），1:3:6 加权选择 χ²=0.43645（13.82），官方 zh_CN 姓氏权重 10 桶 χ²≈11.7644（27.88），相邻整数相关系数≈0.00473（绝对值阈值 0.02）。姓氏权重由 Python 从官方包独立读取。阈值在运行前设定；这是一次宽容差的分布 sanity check，不是 PRNG 质量或密码安全认证，也不是所有 seed 的概率保证。

## 同机子集计时

```powershell
node tools/compare-performance.mjs C:/scratch/faker-reference/site
```

每项 10000 条单字段记录，预热 1 次、测量 7 次。测量包括构造与 JSON 序列化，MoonBit 还包括 JSON 请求解析/校验；双方不计模块载入、Worker 启动、结果 hash 与解析。Python 原 provider 未修改，但采用上述纯 Python xorshift 适配器；该适配器自身开销与默认 RNG 不同。

| 地区 / 方法 | MoonBit JS 中位 ms | 官方 Python + 适配 RNG 中位 ms |
|---|---:|---:|
| en_US / name | 42.06 | 1035.40 |
| en_US / address | 146.95 | 1466.54 |
| zh_CN / name | 18.70 | 347.03 |
| fr_FR / address | 132.02 | 356.16 |

四组双方全部测量结果字节/hash 一致。记录完整样本、CPU、运行时与范围于 `evidence/reference-performance.json`。计时在 bridge 额外参数拒绝规则加入前执行，所测 generate_request 生成路径未变。这些结果不能推广到默认 Faker RNG、所有 provider、峰值内存或端到端服务，不构成完整性能追平。

## 实际浏览器

2026-09-18 本地 IAB 手动操作验收 **8 组**：默认中文/法语切换、日语关联订单与数组、非法 JSON/前向引用的错误状态、长任务取消及恢复、实际 JSONL/CSV 下载、零行 CSV 表头、100 行只预览 50 行、桌面与 390px 响应布局/空错误日志。

下载的 20 行日语关联订单通过 `python tools/check-browser-downloads.py C:/path/to/downloads` 用 Python 标准库独立解析；JSONL 与 CSV 嵌套对象/数组、SKU/价格全部一致，零行 CSV 保留 6 列表头。实际下载文件归档在 evidence/browser-downloads，SHA256 保存在 browser-downloads.json。网页 JS 仅用 textContent 渲染，模块 Worker 可被终止。手机表格内部滚动，页面无横向溢出。临时 viewport 已恢复，验收结束关闭本轮页面/服务。

## 最终证据

`evidence/structured-upgrade.json` 将最终源码/API/真实编译引擎和本轮证据对应到 Git blob；本地提交后运行 `python tools/check-proof.py`。清单不包含自身，旧历史证据不是当前覆盖率。没有新增整体覆盖率主张。完整官方套件、多地区/多版本、任意 provider 参数、多表恢复、长时间和跨平台/精确峰值内存仍未验证。
