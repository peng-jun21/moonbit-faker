///|
fn hex_byte(value : Int) -> String {
  let digits = "0123456789abcdef".to_array()
  digits[value / 16].to_string() + digits[value % 16].to_string()
}

///|
/// RFC 9562 version/variant layout with deterministic, non-secret test bits.
pub fn Generator::uuid4(self : Generator) -> String raise FakeError {
  let bytes = Array::makei(16, _ => self.integer(0, 255))
  bytes[6] = (bytes[6] & 15) | 64
  bytes[8] = (bytes[8] & 63) | 128
  let mut out = ""
  for i, value in bytes {
    if [4, 6, 8, 10].contains(i) {
      out += "-"
    }
    out += hex_byte(value)
  }
  out
}

///|
pub fn Generator::ipv4(self : Generator) -> String raise FakeError {
  self.choose(["192.0.2.", "198.51.100.", "203.0.113."]) +
  self.integer(1, 254).to_string()
}

///|
pub fn Generator::ipv6(self : Generator) -> String raise FakeError {
  let groups = ["2001", "db8"]
  for _ in 0..<6 {
    groups.push(hex_byte(self.integer(0, 255)) + hex_byte(self.integer(0, 255)))
  }
  groups.join(":")
}

///|
pub fn Generator::mac_address(self : Generator) -> String raise FakeError {
  let bytes = Array::makei(6, _ => self.integer(0, 255))
  bytes[0] = (bytes[0] & 252) | 2
  bytes.map(hex_byte).join(":")
}

///|
pub fn Generator::hex_color(self : Generator) -> String raise FakeError {
  "#" + Array::makei(3, _ => hex_byte(self.integer(0, 255))).join("")
}

///|
pub fn Generator::username(self : Generator) -> String raise FakeError {
  "user_" + self.bothify("????????????")
}

///|
pub fn Generator::email(self : Generator) -> String raise FakeError {
  self.username() + "@example.test"
}

///|
pub fn Generator::url(self : Generator) -> String raise FakeError {
  "https://sample-" +
  self.bothify("????????") +
  ".example.test/" +
  self.bothify("??????")
}

///|
pub fn Generator::company(self : Generator) -> String {
  "示例" +
  self.pick([
    "星河", "青山", "晨光", "云帆", "绿洲", "明月", "远航", "海棠",
  ]) +
  self.pick(["科技", "设计", "信息", "文创"]) +
  "有限公司"
}

///|
pub fn Generator::job(self : Generator) -> String {
  self.pick([
    "软件工程师", "产品设计师", "数据分析师", "测试工程师", "项目经理",
    "插画师", "研究助理", "运营专员", "技术写作者", "系统管理员",
    "园艺师", "摄影师",
  ])
}

///|
pub fn Generator::word(self : Generator) -> String {
  self.pick([
    "晨光", "微风", "山林", "海岸", "花园", "星空", "远方", "书页",
    "脚步", "河流", "青石", "落叶", "窗台", "月色", "长街", "灯火",
    "云影", "雨声", "春日", "果实", "旅程", "故事", "时间", "希望",
  ])
}

///|
pub fn Generator::sentence(
  self : Generator,
  words? : Int = 6,
) -> String raise FakeError {
  if words < 1 || words > 100 {
    raise Invalid("sentence words 1..100 required")
  }
  Array::makei(words, _ => self.word()).join("，") + "。"
}

///|
/// Append the GS1 alternating 1/3 modulo-10 check digit to twelve digits.
pub fn ean13_from_body(body : String) -> String raise FakeError {
  let cs = body.to_array()
  if cs.length() != 12 {
    raise Invalid("EAN body needs twelve digits")
  }
  let mut sum = 0
  for i, c in cs {
    if c < '0' || c > '9' {
      raise Invalid("EAN body digits")
    }
    sum += (c.to_int() - 48) * (if i % 2 == 0 { 1 } else { 3 })
  }
  body + ((10 - sum % 10) % 10).to_string()
}

///|
pub fn Generator::ean13(self : Generator) -> String raise FakeError {
  ean13_from_body(self.bothify("############"))
}

///|
/// Checksum-correct 978-prefixed sample, without validating registry allocation.
pub fn Generator::isbn13(self : Generator) -> String raise FakeError {
  ean13_from_body("978" + self.bothify("#########"))
}
