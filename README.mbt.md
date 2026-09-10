# 可执行 API 示例

增加可复现的中文假数据 CSV 导出，符合字段引号和 CRLF 转义规则。这些例子调用公开 API，并随 `moon test` 执行。

```mbt check
///|
test "CSV is deterministic has header and CRLF" {
  let text = @faker.csv(42U, 3)
  assert_eq(text, @faker.csv(42U, 3))
  assert_eq(text.split("\r\n").count(), 5)
  assert_true(text.has_prefix("name,email,address,birth_date,id\r\n\""))
  assert_true(text.contains("@example.test"))
}
```

限制：词库和 provider 规模远小于 Faker；不声称身份号码真实或可用。
