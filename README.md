# 中文 Faker 与结构化测试数据

MoonBit 本地候选版 0.3.0。保留原有 profile/CSV 和种子结果，新增 25 类 provider 配置、字段唯一性、可空值及 JSON/JSONL/CSV 数据表输出。随机生成、校验、配置解析和格式化均由 MoonBit 完成。

## 直接生成数据

已附编译引擎，需要 Node.js 24：

```powershell
node tools/cli.mjs --file examples/orders.json
```

[orders.json](examples/orders.json) 是已执行的五行订单示例。修改 `seed`、`count`、`columns` 或 `format` 后再次运行即可：

```json
{
  "seed": 42,
  "count": 5,
  "format": "json",
  "columns": [
    {"name":"id", "provider":"sequence", "start":1},
    {"name":"customer", "provider":"name"},
    {"name":"price", "provider":"decimal", "min":500, "max":12000, "places":2},
    {"name":"reference", "provider":"uuid4", "unique":true}
  ]
}
```

`format` 可为 `json`、`jsonl`、`csv`，默认为 JSON 数组。字段名保持给定名称；CSV 按 columns 顺序输出，所有字段正确加引号并使用 CRLF。CSV 的 null 输出为空字段，JSON 保留 null。零行 JSONL 输出为空。

原用法仍可使用：`node tools/cli.mjs --input "42 5"`。网页启动命令为 `./start-review.ps1`，地址 http://127.0.0.1:8798/web/ ，也接受 JSON 配置。`--json` 是旧 CLI 的结果包装选项，直接取得数据表时可省略。

## Provider 配置

| provider | 附加参数与输出 |
|---|---|
| name / address | 原创小词表中文姓名、带“测试省”标记的地址 |
| email / username / url | ASCII 用户名、example.test 邮箱、HTTPS 示例 URL |
| uuid4 / ipv4 / ipv6 / mac / color | UUIDv4 位布局、文档用 IP、局部管理单播 MAC、十六进制颜色 |
| company / job / word | 带“示例”标记的公司、小型职业/词语表 |
| sentence | `words`，默认 6，范围 1–100；词语列表式中文测试文本 |
| boolean | `percent`，默认 50，范围 0–100 |
| integer | `min` / `max`，默认 0 / 100，含端点 |
| decimal | `min` / `max` 是缩放后的整数，`places` 为 0–6；返回保留末尾零的字符串 |
| date | `first` / `last` 为 YYYY-MM-DD，默认 2000-01-01 / 2030-12-31，含端点 |
| ean13 / isbn13 | 带 modulo-10 校验位的样本；ISBN 样本固定 978 前缀 |
| template | `template`，默认 `????-####`；`#` 数字、`?` 小写字母，反斜杠转义 |
| choice | 非空字符串数组 `values` |
| weighted_choice | `values` 与等长整数数组 `weights`；零权重不选，权重总和须为 1–1,000,000,000 |
| constant | 标量 `value`：字符串、数值、布尔或 null |
| sequence | `start` / `step`，默认 0 / 1；按行号计算，不消耗随机数 |

每列支持 `unique`（默认 false）和 `null_percent`（默认 0）。唯一性只在一次 records 调用的同一列内生效，null 也占一个唯一值；每个值最多尝试 1,000 次，超出会明确报错。小值域或偏斜权重可能触发重试上限，不能将该错误一律解释成已穷尽所有可能值。未知参数、重复列名、非法类型和范围会报错。

## MoonBit API

- `Generator::choose/sample/weighted_index/boolean/decimal/bothify` 提供基础采样；sample 不修改输入数组，按不同输入位置抽样。
- `snapshot/restore` 保存恢复 PRNG 状态。它只包含随机源状态；records 的唯一值集合是每次调用新建的。
- `Generator::value` 接受 `Provider`；`Column::new`、`records` 和 `render_records` 用于组合标量数据表；`generate_request` 接受上述 JSON 配置。
- 原 `dataset`、`profile`、`csv`、`name`、`date` 保持种子样例结果；新 `date_between` 按日历日生成明确区间内的日期。

精确签名见 [pkg.generated.mbti](pkg.generated.mbti)，示例见 [README.mbt.md](README.mbt.md)。

## 范围与限制

这是确定性的测试数据生成器。随机源为原有 32 位 xorshift 状态，可预测；相同种子、调用顺序和配置可重现数据。UUID 校验只涵盖版本/variant 与格式，未提供生产随机源或跨进程唯一性保证。邮箱使用 `.test`；IPv4 来自 TEST-NET 三段，IPv6 来自 `2001:db8::/32`。

EAN/ISBN 只生成长度、前缀和校验位正确的样本，未验证 GS1/ISBN 分配、注册者或出版物。姓名可能与真人相同；地址和公司明确标记为示例。词库与地区覆盖仍远小于 Python Faker，不提供完整 provider/locale、嵌套对象、关系数据、统计分布保证或流式生成，不能判定追平。

单次最多 10,000 行、32 列、100,000 个单元格；字段字符串最多 4,096 个 UTF-16 单元，生成/渲染记录正文预算 8,000,000 单元，总尝试次数最多 1,000,000。整数/缩放整数/序列值限制在 ±1,000,000,000；种子为 UInt32。格式预算按 UTF-16 内容计数，不是磁盘字节上限。

## 验证与来源

本轮 16 项 JS 测试、新增 8 项 Wasm-GC 测试通过，含原种子样例和 GS1 公开校验向量。256 行×26 列的三种格式通过 Python 标准库独立验证；10 个错误配置及实际 schema 文件/空 JSONL CLI 场景通过。一万行×六列的单次本机测量记录在 evidence，属于一次测量。完整范围见 [TESTING.md](TESTING.md)。

参考 [Faker zh_CN](https://faker.readthedocs.io/en/master/locales/zh_CN.html) 的公开能力独立实现，没有复制其词库或代码。格式依据 [UUID RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html)、[IPv4 RFC 5737](https://www.rfc-editor.org/rfc/rfc5737.html)、[IPv6 RFC 3849](https://www.rfc-editor.org/rfc/rfc3849.html) 和 [GS1 校验位说明](https://www.gs1.org/services/how-calculate-check-digit-manually)。本仓库源码为 MIT。

安装 MoonBit 后可运行 `./verify.ps1`，或传 `-MoonPath C:/path/to/moon/bin/moon.exe`。所有内容仅本地，独立 Git/构建目录、无 remote；未上传、发布或提交比赛。旧 ZIP/bundle 为历史快照，本轮未重打包。
