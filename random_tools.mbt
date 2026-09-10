///|
/// PRNG-only checkpoint, not a cryptographic seed or a uniqueness-state snapshot.
pub fn Generator::snapshot(self : Generator) -> UInt {
  self.state
}

///|
pub fn Generator::restore(
  self : Generator,
  state : UInt,
) -> Unit raise FakeError {
  if state == 0U {
    raise Invalid("xorshift state must be nonzero")
  }
  self.state = state
}

///|
pub fn[T] Generator::choose(
  self : Generator,
  items : Array[T],
) -> T raise FakeError {
  if items.is_empty() || items.length() > 100000 {
    raise Invalid("choice length 1..100000 required")
  }
  items[self.integer(0, items.length() - 1)]
}

///|
/// Sample distinct input positions without changing the source array.
pub fn[T] Generator::sample(
  self : Generator,
  items : Array[T],
  count : Int,
) -> Array[T] raise FakeError {
  if items.length() > 100000 || count < 0 || count > items.length() {
    raise Invalid("sample size")
  }
  let copy = items.copy()
  for i in 0..<count {
    let j = self.integer(i, copy.length() - 1)
    let value = copy[i]
    copy[i] = copy[j]
    copy[j] = value
  }
  copy[0:count].to_owned()
}

///|
fn weight_total(weights : Array[Int]) -> Int raise FakeError {
  if weights.is_empty() || weights.length() > 100000 {
    raise Invalid("weight count")
  }
  let mut total = 0
  for weight in weights {
    if weight < 0 || weight > 1000000000 - total {
      raise Invalid("weight total 1..1000000000 required")
    }
    total += weight
  }
  if total == 0 {
    raise Invalid("at least one positive weight required")
  }
  total
}

///|
pub fn Generator::weighted_index(
  self : Generator,
  weights : Array[Int],
) -> Int raise FakeError {
  let mut value = self.integer(0, weight_total(weights) - 1)
  for i, weight in weights {
    if value < weight {
      return i
    }
    value -= weight
  }
  abort("unreachable weighted choice")
}

///|
pub fn Generator::boolean(
  self : Generator,
  percent? : Int = 50,
) -> Bool raise FakeError {
  if percent < 0 || percent > 100 {
    raise Invalid("percentage 0..100 required")
  }
  self.integer(1, 100) <= percent
}

///|
pub fn Generator::decimal(
  self : Generator,
  min_scaled : Int,
  max_scaled : Int,
  places : Int,
) -> String raise FakeError {
  if places < 0 || places > 6 {
    raise Invalid("decimal places 0..6 required")
  }
  let number = self.integer(min_scaled, max_scaled)
  let magnitude = if number < 0 { -number } else { number }
  let mut scale = 1
  for _ in 0..<places {
    scale *= 10
  }
  let sign = if number < 0 { "-" } else { "" }
  if places == 0 {
    return sign + magnitude.to_string()
  }
  let mut fraction = (magnitude % scale).to_string()
  while fraction.length() < places {
    fraction = "0" + fraction
  }
  sign + (magnitude / scale).to_string() + "." + fraction
}

///|
pub fn Generator::bothify(
  self : Generator,
  template : String,
) -> String raise FakeError {
  if template.length() > 4096 {
    raise Invalid("template length")
  }
  let cs = template.to_array()
  let alphabet = "abcdefghijklmnopqrstuvwxyz".to_array()
  let mut result = ""
  let mut escaped = false
  for c in cs {
    if escaped {
      result += c.to_string()
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else if c == '#' {
      result += self.integer(0, 9).to_string()
    } else if c == '?' {
      result += alphabet[self.integer(0, 25)].to_string()
    } else {
      result += c.to_string()
    }
  }
  if escaped {
    raise Invalid("trailing template escape")
  }
  result
}
