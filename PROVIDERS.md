# 标量 Provider

原有 provider 与种子结果保留。下列唯一性说明适用于旧 records 调用；Session 的集合持续到关闭或恢复检查点。

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


新增 `localized`：`locale` 默认 en_US，`method` 默认 name。地区为 en_US、zh_CN、en_GB、de_DE、fr_FR、ja_JP；可用方法因地区而异，使用 `locale_methods(locale)` 或 `session_request('{"op":"catalog"}')` 查看精确目录。217 个公开地区/方法组合包含姓名、地址、公司、职业、颜色、词语等子集。地区回退遵循被固定的 Faker 数据，不保证每项返回该地区语言。
