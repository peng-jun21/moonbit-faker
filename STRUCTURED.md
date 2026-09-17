# 结构、关联与会话契约

单数据集任务使用 `seed`、`count`、`schema`（或互斥的 `columns`）、可选 `tables`、`format`。嵌套节点中 `name` 是父 object 内字段名称；数组 items、nullable/unique 的 value、join 的 parts 不需要 name。字段按声明顺序求值，未知配置项报错。

| 节点 | 配置 | 语义 |
|---|---|---|
| provider 叶子 | 原有 provider 选项 | 支持 unique、null_percent 简写 |
| object | `fields: [{name,...node}]` | 字段名非空且不重复 |
| array | `items: node, min: 0, max: 3` | 长度在含端点区间内 |
| nullable | `value: node, percent: 50` | percent 为 0–100 |
| unique | `value: scalarNode` | 标量或可空标量；不支持对象/数组的整体唯一性 |
| ref | `path: "/customer/id"` | 本行先前已完成字段；拒绝前向/缺失引用 |
| foreign | `table: "customers", path: ""` | 从外表均匀抽一行，再读取 JSON pointer；空 path 返回整行 |
| join | `parts: [node,...], separator: " "` | 仅拼接标量，null 视为空字符串 |

JSON pointer 使用 `~0` 表示 `~`、`~1` 表示 `/`；数组索引必须是无多余前导零的非负整数。ref 不会读取上一行。两个独立 foreign 节点会分别抽样；要让相关列属于同一客户，应先用一个 foreign 得到客户对象，再用 ref 读取 ID、姓名。

示例 [nested-orders.json](examples/nested-orders.json) 绑定商品表，生成商品对象、同源 SKU/价格和标签数组。可在网页 JSON 配置运行，也可交给 stream CLI；旧 generate_request 的 schema 路径只提供 JSON/JSONL 整批输出。

## 多表任务

[related-shop.json](examples/related-shop.json) 依次生成 100 个客户、1000 条订单。顶层 `datasets` 中每个条目有唯一 `name`、`count`、`seed` 和 schema/columns。foreign 只能引用先前数据集；需要被引用的数据集必须非空且不超过 50000 行。

输出是 JSONL，每行形如 `{"dataset":"orders","row":{...}}`。宿主仅保留被后续数据集引用的表；保留内容有预算，因此不承诺任意复杂度的 50000 行都可容纳。此入口暂不支持 CSV、顶层 tables 或多表暂停恢复。每个数据集有独立 seed 和唯一集合。

## 状态和失败

唯一性按 schema 节点身份记录，跨行、跨批次持续；同一数组 items 节点的所有元素共用集合。null 也是一个唯一值。每个唯一值最多尝试 1000 次，偏斜分布可能提前碰到重试限制，不一定意味着数学值域已耗尽。sequence 依据行号计算，在数组中也不是逐元素计数器。

Session 拥有 schema 中可变数组、绑定表和恢复后的状态副本；调用者修改输入或已返回行不会修改内部外表。单次 next 失败时，随机源、行号、已提交唯一集合全部保持原状。restore 先验证完整候选，再替换原状态。

Node 的一次批请求可能返回错误前已成功的行；generateJob 先交付这些行，再抛错。写入回调抛错、取消和超时会关闭 Worker；不返回已交付部分的可恢复检查点。正常 `limit` 停止才产生可恢复状态。每次 Worker 操作默认 30 秒超时，范围 1–300000ms；这不是总任务时限。

## 资源边界

| 层 | 边界 |
|---|---|
| 地区模板 | 展开深度 16、输出 4096 个 UTF-16 单元 |
| schema | 深度 16、总节点 1024；每对象 128 字段；数组长度 0–1000；join 128 部分 |
| 单行 | 求值次数 100000；内容与最终序列化各有 1000000 个 UTF-16 单元上限 |
| 唯一集合 | 全会话合计 200000 项、规范化 JSON 键文本 8000000 个 UTF-16 单元 |
| 绑定外表 | 16 表、每表 1–50000 行；合计 200000 JSON 节点、8000000 文本单元、深度 16 |
| 会话 | 行位置最多 1000000000；JSON bridge 最多 16 个活动 handle，请显式 close |
| 旧平面整批入口 | 10000 行、32 列、100000 单元格、正文 8000000 UTF-16 单元 |
| schema 整批入口 | 10000 行、正文 8000000 UTF-16 单元；仍有会话/单行限制 |
| Node stream | 每数据集最多 10000000 行；批大小 1–256，约 1MiB 序列化后停止继续填批；单条最大行可使批大小超过 1MiB |
| Worker | JS old-generation heap 512MiB 配置；并非进程 RSS 上限 |
| CLI | 输入 16MiB、检查点 64MiB；输出默认 256MiB，可调至 2147483647 字节；检查点要求文件输出 |
| 网页 | 1000 行、5000000 个 JSON 字符；表格预览 50 行；30 秒超时 |

多个上限同时适用：例如 1000 万行不意味着可以保存 1000 万个唯一值。字符串预算以 UTF-16 单元计，CLI 文件预算以 UTF-8 字节计，两者不能互换。对象/数组 CSV 单元格使用 JSON，null 为空字符串；CSV 每段都有表头和 CRLF，保留字段声明顺序。
