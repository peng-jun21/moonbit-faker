# Faker 测试数据工坊

MoonBit 本地候选版 **0.4.0**。可复现的六地区姓名/地址等数据、嵌套对象和数组、行内引用、跨表关联、持续唯一性，以及带背压与检查点的 JSONL/CSV 流式生成。保留原有 profile 和 25 类标量 provider 的种子结果。

## 运行

仓库附有真实编译的 MoonBit JS 引擎。文件入口需要 Node.js 24，不需要 npm 依赖：

```powershell
node tools/stream.mjs --job examples/people-localized.json --out people.jsonl
node tools/stream.mjs --job examples/nested-orders.json --out orders.jsonl
node tools/stream.mjs --job examples/related-shop.json --out shop.jsonl
```

默认拒绝覆盖已有文件；明确使用 `--force` 才替换。未指定 `--out` 时写 stdout，未指定 `--job` 或 `--resume` 时读取 UTF-8 JSON stdin。`node tools/stream.mjs --help` 列出超时、字节上限等选项。

网页：运行 `./start-review.ps1` 后打开 <http://127.0.0.1:8798/web/>。切换地区和示例，预览前 50 行，下载全部结果；网页最多 1000 行，支持取消和 JSON 配置。网页不会把数据发到第三方。

原入口仍可用：`node tools/cli.mjs --input "42 5"`、`node tools/cli.mjs --file examples/orders.json`。旧入口支持 JSON 数组、JSONL 和 CSV 的整批输出；新 stream 入口支持 JSONL 和 CSV，不收集整份输出数组。

## 地区与结构

地区为 `en_US`、`zh_CN`、`en_GB`、`de_DE`、`fr_FR`、`ja_JP`。新增字段配置：

```json
{"name":"customer","provider":"localized","locale":"zh_CN","method":"name"}
```

共有 **217 个公开地区/方法组合**，方法因地区而异。`locale_methods(locale)` 或 JS 导出的 `session('{"op":"catalog"}')` 返回精确目录。部分 provider 按 Faker 的默认规则回退到其他地区，例如部分地区的颜色或词语数据；不保证所有方法都返回对应语言。

`schema` 支持 object、array、nullable、unique、ref、foreign、join。先抽取外表整条记录，再引用其中字段，可保持订单中的客户 ID、姓名一致。规则和运行边界见 [STRUCTURED.md](STRUCTURED.md)；标量选项见 [PROVIDERS.md](PROVIDERS.md)。

## 暂停与恢复

```powershell
node tools/stream.mjs --job examples/people-localized.json --limit 200 --out part-1.jsonl --checkpoint state.json
node tools/stream.mjs --resume state.json --out part-2.jsonl
```

原任务是 1000 行，第二条命令接着生成剩余 800 行。两段 JSONL 按顺序拼接，与不中断的同版本任务逐字节一致；唯一集合、随机状态、行号和绑定表均被恢复。恢复前会核对检查点与上一段文件的 SHA256 和长度。每段 CSV 都有表头，合并时需移除后续段表头。

暂停恢复目前只适用于单数据集。输出采用同目录临时文件，完成后发布；出错时不留下半份目标数据文件，stdout 则可能已输出成功的行。数据文件与检查点**分别发布，并非两文件事务**：若检查点发布失败，数据文件可能已经存在，命令返回失败；应检查结果再处理。SHA256 用于发现意外修改，不提供身份认证。

## MoonBit 与 Node API

- 原 `Generator`、`Provider`、`Column`、`records`、`render_records`、`generate_request` 继续可用。`Generator::localized` 使用地区词库。
- `parse_spec` / `Spec` 创建结构，`Session::new` / `open_session` 创建有状态生成器。
- `Session::bind_table` 复制外表；`next` 成功后才提交行号、随机状态和唯一值。失败不会消耗这些状态。
- `checkpoint` / `restore` 保存恢复整个会话；配置不匹配或损坏的恢复操作不会修改原会话。它不同于只保存 PRNG 的旧 `Generator::snapshot`。
- `tools/session-runtime.mjs` 的 `generateJob(job, asyncWrite, options)` 等待消费者完成每次写入，支持 AbortSignal、批大小、超时、进度和单表检查点。高级 `DataSession` 使用完毕后必须 `await close()`；同一会话不允许并发操作。

精确签名见 [pkg.generated.mbti](pkg.generated.mbti)，旧基础例子见 [README.mbt.md](README.mbt.md)。

## 已验证与未覆盖

JS、Wasm-GC 各 22 组测试；官方 Faker 40.39.0 的 651 组/5208 个地区输出逐项一致；9 组 Node 宿主检查包括十万行流式、真实 CLI 暂停恢复、取消、背压、错误处理和独立 CSV 解析。十万行统计检查、实际网页及下载检查已记录。[TESTING.md](TESTING.md) 提供范围、计时口径与复现命令。

随机源仍为可预测的 32 位 xorshift。官方对照明确替换了参考随机源，以检验原官方 provider 的词库、权重和格式；**不兼容 Faker 默认 MT19937 的种子序列**。四个一万行任务的同机计时包含构造和序列化，不能推广为完整性能追平。完整 provider/API/地区、扩展插件、所有官方测试、多表恢复和跨平台长期运行仍有差距，见 [FEATURES.md](FEATURES.md) 与 [ROADMAP.md](ROADMAP.md)。

UUID/EAN/ISBN 等是格式测试样本，无生产随机源、实际注册分配或跨进程唯一性保证。原 email/IP 使用示例域名/文档地址；本地化姓名、地址、公司来自现实词库，可能与真实信息重合。资源上限与各入口差异见 STRUCTURED.md。

## 来源和本地验证

地区词库、权重和模板来自固定版本 [Faker 40.39.0](https://pypi.org/project/Faker/40.39.0/) 的官方 wheel，共 225 张内部/公开表、28847 个条目（含回退和不同性别中的重复项，不是去重词汇量）。[data/provenance.json](data/provenance.json) 保存 wheel、来源文件和数据 SHA256；[Faker MIT 许可证](third_party/Faker-LICENSE.txt) 随数据保留。本地生成、状态和宿主代码独立实现，仓库源码使用 MIT。

安装 MoonBit、Python 和 Node.js 后运行 `./verify.ps1`，也可传 `-MoonPath C:/path/to/moon/bin/moon.exe`。日常验证只用仓库内已捕获的官方输出，不需下载 Faker；重新执行官方对照需按 TESTING.md 建立外部参考目录。

全部仅本地，独立 Git/构建目录、无 remote；未上传、发布或提交比赛。旧 ZIP/bundle 为历史快照，本轮未重打包。
