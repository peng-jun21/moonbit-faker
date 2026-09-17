///|
pub(all) enum Provider {
  Name
  Address
  Email
  Username
  Url
  Uuid4
  Ipv4
  Ipv6
  MacAddress
  HexColor
  Company
  Job
  Word
  Sentence(Int)
  Boolean(Int)
  Integer(Int, Int)
  Decimal(Int, Int, Int)
  DateBetween(String, String)
  Ean13
  Isbn13
  Template(String)
  Choice(Array[String])
  WeightedChoice(Array[String], Array[Int])
  Constant(Json)
  Sequence(Int, Int)
  Localized(String, String)
} derive(Debug, Eq, ToJson)

///|
pub(all) struct Column {
  name : String
  provider : Provider
  unique : Bool
  null_percent : Int
} derive(Debug, Eq)

///|
pub fn Column::new(
  name : String,
  provider : Provider,
  unique? : Bool = false,
  null_percent? : Int = 0,
) -> Column {
  { name, provider, unique, null_percent, }
}

///|
fn bounds(min : Int, max : Int) -> Unit raise FakeError {
  if min > max || min < -1000000000 || max > 1000000000 {
    raise Invalid("integer bounds")
  }
}

///|
fn scalar(value : Json) -> Json raise FakeError {
  match value {
    String(s) => {
      if s.length() > 4096 {
        raise Invalid("scalar string length")
      }
      Json::string(s)
    }
    Number(n, ..) => {
      if n.is_nan() || n.is_inf() {
        raise Invalid("non-finite JSON number")
      }
      Json::number(n)
    }
    Null | True | False => value
    _ => raise Invalid("only scalar constant values supported")
  }
}

///|
fn choice_values(values : Array[String]) -> Unit raise FakeError {
  if values.is_empty() || values.length() > 10000 {
    raise Invalid("choice count 1..10000 required")
  }
  let mut total = 0
  for value in values {
    total += value.length()
    if value.length() > 4096 || total > 1000000 {
      raise Invalid("choice text budget")
    }
  }
}

///|
fn sequence_value(start : Int, step : Int, index : Int) -> Int raise FakeError {
  let value = start.to_int64() + step.to_int64() * index.to_int64()
  if value < -1000000000L || value > 1000000000L {
    raise Invalid("sequence bounds")
  }
  value.to_int()
}

///|
fn Provider::validate(self : Provider) -> Unit raise FakeError {
  match self {
    Localized(locale, provider_name) => {
      ignore(locale_table(locale, provider_name))
      if provider_name.has_prefix("postcode_set_") {
        raise Invalid("internal locale table")
      }
    }
    Integer(min, max) => bounds(min, max)
    Decimal(min, max, places) => {
      bounds(min, max)
      if places < 0 || places > 6 {
        raise Invalid("decimal places")
      }
    }
    DateBetween(first, last) =>
      if ordinal(first) > ordinal(last) {
        raise Invalid("reversed date range")
      }
    Sentence(n) => if n < 1 || n > 100 { raise Invalid("sentence words") }
    Boolean(n) => if n < 0 || n > 100 { raise Invalid("boolean percentage") }
    Choice(values) => choice_values(values)
    WeightedChoice(values, weights) => {
      choice_values(values)
      if values.length() != weights.length() {
        raise Invalid("choice weight length")
      }
      ignore(weight_total(weights))
    }
    Template(template) => {
      if template.length() > 4096 {
        raise Invalid("template length")
      }
      let mut escaped = false
      for c in template {
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        }
      }
      if escaped {
        raise Invalid("trailing template escape")
      }
    }
    Constant(value) => ignore(scalar(value))
    Sequence(start, step) => {
      bounds(start, start)
      bounds(step, step)
    }
    _ => ()
  }
}

///|
fn Generator::provide(
  self : Generator,
  provider : Provider,
  index : Int,
) -> Json raise FakeError {
  match provider {
    Localized(locale, provider_name) =>
      Json::string(self.localized(locale, provider_name))
    Name => Json::string(self.name())
    Address => Json::string(self.profile(index).address)
    Email => Json::string(self.email())
    Username => Json::string(self.username())
    Url => Json::string(self.url())
    Uuid4 => Json::string(self.uuid4())
    Ipv4 => Json::string(self.ipv4())
    Ipv6 => Json::string(self.ipv6())
    MacAddress => Json::string(self.mac_address())
    HexColor => Json::string(self.hex_color())
    Company => Json::string(self.company())
    Job => Json::string(self.job())
    Word => Json::string(self.word())
    Sentence(n) => Json::string(self.sentence(words=n))
    Boolean(percent) => Json::boolean(self.boolean(percent~))
    Integer(min, max) => self.integer(min, max).to_json()
    Decimal(min, max, places) => Json::string(self.decimal(min, max, places))
    DateBetween(first, last) => Json::string(self.date_between(first, last))
    Ean13 => Json::string(self.ean13())
    Isbn13 => Json::string(self.isbn13())
    Template(template) => Json::string(self.bothify(template))
    Choice(values) => Json::string(self.choose(values))
    WeightedChoice(values, weights) =>
      Json::string(values[self.weighted_index(weights)])
    Constant(value) => scalar(value)
    Sequence(start, step) => sequence_value(start, step, index).to_json()
  }
}

///|
/// Generate one provider value. Sequence index is explicit and does not consume RNG.
pub fn Generator::value(
  self : Generator,
  provider : Provider,
  index? : Int = 0,
) -> Json raise FakeError {
  if index < 0 || index > 1000000000 {
    raise Invalid("provider index")
  }
  provider.validate()
  self.provide(provider, index)
}

///|
/// Flat scalar records. Per-column uniqueness includes null and has bounded retries.
pub fn records(
  seed : UInt,
  columns : Array[Column],
  count : Int,
) -> Array[Json] raise FakeError {
  if count < 0 ||
    count > 10000 ||
    columns.is_empty() ||
    columns.length() > 32 ||
    count * columns.length() > 100000 {
    raise Invalid("record dimensions exceed budget")
  }
  let names : Map[String, Bool] = Map([])
  let seen : Array[Map[String, Bool]] = []
  for column in columns {
    if column.name.is_empty() ||
      column.name.length() > 80 ||
      names.contains(column.name) {
      raise Invalid("invalid or duplicate column name")
    }
    names[column.name] = true
    if column.null_percent < 0 || column.null_percent > 100 {
      raise Invalid("null percentage")
    }
    column.provider.validate()
    if column.provider is Sequence(start, step) {
      ignore(sequence_value(start, step, if count > 0 { count - 1 } else { 0 }))
    }
    seen.push(Map([]))
  }
  let generator = Generator::new(seed)
  let rows = []
  let mut attempts = 0
  let mut size = 0
  for index in 0..<count {
    let row : Map[String, Json] = Map([])
    for c, column in columns {
      let mut accepted = false
      for _ in 0..<1000 {
        attempts += 1
        if attempts > 1000000 {
          raise Invalid("generation attempt budget")
        }
        let value = if column.null_percent > 0 &&
          generator.boolean(percent=column.null_percent) {
          Json::null()
        } else {
          generator.provide(column.provider, index)
        }
        let key = value.stringify()
        if column.unique && seen[c].contains(key) {
          continue
        }
        if column.unique {
          seen[c][key] = true
        }
        row[column.name] = value
        accepted = true
        break
      }
      if !accepted {
        raise Invalid("unique retry budget for column " + column.name)
      }
    }
    let value = Json::object(row)
    size += value.stringify().length()
    if size > 8000000 {
      raise Invalid("record output budget")
    }
    rows.push(value)
  }
  rows
}

///|
pub fn render_records(
  columns : Array[Column],
  rows : Array[Json],
  format : String,
) -> String raise FakeError {
  if !["json", "jsonl", "csv"].contains(format) {
    raise Invalid("format must be json, jsonl or csv")
  }
  if rows.length() > 10000 ||
    columns.is_empty() ||
    columns.length() > 32 ||
    rows.length() * columns.length() > 100000 {
    raise Invalid("render dimensions exceed budget")
  }
  let seen : Map[String, Bool] = Map([])
  for column in columns {
    if column.name.is_empty() ||
      column.name.length() > 80 ||
      seen.contains(column.name) {
      raise Invalid("invalid or duplicate column name")
    }
    seen[column.name] = true
  }
  let canonical = []
  let mut size = 0
  for row in rows {
    let source = object(row)
    if source.length() != columns.length() {
      raise Invalid("row column count mismatch")
    }
    let clean : Map[String, Json] = Map([])
    for column in columns {
      clean[column.name] = scalar(required(source, column.name))
    }
    let value = Json::object(clean)
    size += value.stringify().length()
    if size > 8000000 {
      raise Invalid("render output budget")
    }
    canonical.push(value)
  }
  if format == "json" {
    return Json::array(canonical).stringify()
  }
  if format == "jsonl" {
    return if canonical.is_empty() {
      ""
    } else {
      canonical.map(row => row.stringify()).join("\n") + "\n"
    }
  }
  fn quote(s : String) -> String {
    "\"" + s.replace_all(old="\"", new="\"\"") + "\""
  }
  let lines = [columns.map(c => quote(c.name)).join(",")]
  for row in canonical {
    let object = match row {
      Object(object) => object
      _ => raise Invalid("CSV row must be an object")
    }
    let cells = []
    for column in columns {
      let value = match object.get(column.name) {
        Some(v) => scalar(v)
        None => raise Invalid("missing CSV column")
      }
      cells.push(
        quote(
          match value {
            String(s) => s
            Null => ""
            _ => value.stringify()
          },
        ),
      )
    }
    lines.push(cells.join(","))
  }
  lines.join("\r\n") + "\r\n"
}
