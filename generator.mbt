///|
pub suberror FakeError {
  Invalid(String)
} derive(Debug)

///|
pub struct Generator {
  mut state : UInt
} derive(Debug)

///|
pub(all) struct Profile {
  name : String
  email : String
  address : String
  birth_date : String
  id : String
} derive(Debug, Eq)

///|
pub fn Generator::new(seed : UInt) -> Generator {
  { state: if seed == 0U { 0x9e3779b9U } else { seed }, }
}

///|
fn Generator::next(self : Generator) -> UInt {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  x
}

///|
pub fn Generator::integer(
  self : Generator,
  min : Int,
  max : Int,
) -> Int raise FakeError {
  if min > max || min < -1000000000 || max > 1000000000 {
    raise Invalid("integer bounds")
  }
  let span = (max - min + 1).reinterpret_as_uint()
  let threshold = (0U - span) % span
  let mut x = self.next()
  while x < threshold {
    x = self.next()
  }
  min + (x % span).reinterpret_as_int()
}

///|
fn Generator::pick(self : Generator, values : Array[String]) -> String {
  values[(self.next() % values.length().reinterpret_as_uint()).reinterpret_as_int()]
}

///|
pub fn Generator::name(self : Generator) -> String {
  self.pick([
    "赵", "钱", "孙", "李", "周", "吴", "郑", "王", "陈", "林", "黄",
    "张", "刘", "杨", "许", "叶",
  ]) +
  self.pick([
    "明", "雨桐", "子安", "清和", "若云", "小川", "嘉宁", "星辰",
    "思远", "晓月", "文静", "知秋",
  ])
}

///|
fn pad(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
pub fn Generator::date(
  self : Generator,
  first_year : Int,
  last_year : Int,
) -> String raise FakeError {
  if first_year < 1 || last_year > 9999 {
    raise Invalid("year bounds")
  }
  let y = self.integer(first_year, last_year)
  let m = self.integer(1, 12)
  let leap = y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)
  let days = if m == 2 {
    if leap {
      29
    } else {
      28
    }
  } else if m == 4 || m == 6 || m == 9 || m == 11 {
    30
  } else {
    31
  }
  (if y < 10 {
    "000"
  } else if y < 100 {
    "00"
  } else if y < 1000 {
    "0"
  } else {
    ""
  }) +
  y.to_string() +
  "-" +
  pad(m) +
  "-" +
  pad(self.integer(1, days))
}

///|
pub fn Generator::profile(
  self : Generator,
  index : Int,
) -> Profile raise FakeError {
  if index < 0 {
    raise Invalid("negative index")
  }
  let name = self.name()
  let place = self.pick([
    "测试省示例市东城区", "测试省示例市西城区", "测试省样本市新区",
  ])
  let road = self.pick(["星河路", "青山路", "明月街", "样本大道"])
  let address = place + road + self.integer(1, 999).to_string() + "号"
  let id = "sample-" + index.to_string() + "-" + self.next().to_string()
  {
    name,
    email: "sample" + index.to_string() + "@example.test",
    address,
    birth_date: self.date(1970, 2005),
    id,
  }
}

///|
pub fn dataset(seed : UInt, count : Int) -> Array[Profile] raise FakeError {
  if count < 0 || count > 10000 {
    raise Invalid("count must be 0..10000")
  }
  let g = Generator::new(seed)
  Array::makei(count, i => g.profile(i))
}
