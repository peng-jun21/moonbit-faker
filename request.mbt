///|
fn object(value : Json) -> Map[String, Json] raise FakeError {
  match value {
    Object(fields) => fields
    _ => raise Invalid("JSON object required")
  }
}

///|
fn text_option(
  fields : Map[String, Json],
  key : String,
  fallback : String,
) -> String raise FakeError {
  match fields.get(key) {
    None => fallback
    Some(String(value)) => value
    _ => raise Invalid("string option required: " + key)
  }
}

///|
fn int_option(
  fields : Map[String, Json],
  key : String,
  fallback : Int,
) -> Int raise FakeError {
  match fields.get(key) {
    None => fallback
    Some(value) =>
      @json.from_json(value) catch {
        _ => raise Invalid("integer option required: " + key)
      }
  }
}

///|
fn required(fields : Map[String, Json], key : String) -> Json raise FakeError {
  match fields.get(key) {
    Some(value) => value
    None => raise Invalid("missing option: " + key)
  }
}

///|
fn string_options(
  fields : Map[String, Json],
  key : String,
) -> Array[String] raise FakeError {
  @json.from_json(required(fields, key)) catch {
    _ => raise Invalid("string array required: " + key)
  }
}

///|
fn reject_unknown(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Unit raise FakeError {
  for key, _ in fields {
    if !allowed.contains(key) {
      raise Invalid("unknown option: " + key)
    }
  }
}

///|
fn parse_column(value : Json) -> Column raise FakeError {
  let fields = object(value)
  let name = text_option(fields, "name", "")
  let kind = text_option(fields, "provider", "")
  let extra = match kind {
    "integer" => ["min", "max"]
    "decimal" => ["min", "max", "places"]
    "date" => ["first", "last"]
    "boolean" => ["percent"]
    "sentence" => ["words"]
    "template" => ["template"]
    "choice" => ["values"]
    "weighted_choice" => ["values", "weights"]
    "constant" => ["value"]
    "sequence" => ["start", "step"]
    _ => []
  }
  let allowed = ["name", "provider", "unique", "null_percent"]
  for key in extra {
    allowed.push(key)
  }
  reject_unknown(fields, allowed)
  let provider = match kind {
    "name" => Name
    "address" => Address
    "email" => Email
    "username" => Username
    "url" => Url
    "uuid4" => Uuid4
    "ipv4" => Ipv4
    "ipv6" => Ipv6
    "mac" => MacAddress
    "color" => HexColor
    "company" => Company
    "job" => Job
    "word" => Word
    "sentence" => Sentence(int_option(fields, "words", 6))
    "boolean" => Boolean(int_option(fields, "percent", 50))
    "integer" =>
      Integer(int_option(fields, "min", 0), int_option(fields, "max", 100))
    "decimal" =>
      Decimal(
        int_option(fields, "min", 0),
        int_option(fields, "max", 10000),
        int_option(fields, "places", 2),
      )
    "date" =>
      DateBetween(
        text_option(fields, "first", "2000-01-01"),
        text_option(fields, "last", "2030-12-31"),
      )
    "ean13" => Ean13
    "isbn13" => Isbn13
    "template" => Template(text_option(fields, "template", "????-####"))
    "choice" => Choice(string_options(fields, "values"))
    "weighted_choice" => {
      let weights : Array[Int] = @json.from_json(required(fields, "weights")) catch {
        _ => raise Invalid("integer weight array required")
      }
      WeightedChoice(string_options(fields, "values"), weights)
    }
    "constant" => Constant(required(fields, "value"))
    "sequence" =>
      Sequence(int_option(fields, "start", 0), int_option(fields, "step", 1))
    _ => raise Invalid("unknown provider: " + kind)
  }
  let unique = match fields.get("unique") {
    None | Some(False) => false
    Some(True) => true
    _ => raise Invalid("unique must be boolean")
  }
  Column::new(
    name,
    provider,
    unique~,
    null_percent=int_option(fields, "null_percent", 0),
  )
}

///|
/// JSON request with seed/count/columns/format; output is json, jsonl, or CSV.
pub fn generate_request(request : String) -> String raise FakeError {
  if request.length() > 1000000 {
    raise Invalid("request length budget")
  }
  let input = @json.parse(request) catch {
    _ => raise Invalid("invalid JSON request")
  }
  let fields = object(input)
  reject_unknown(fields, ["seed", "count", "columns", "format"])
  let seed : UInt = match fields.get("seed") {
    None => 0U
    Some(value) =>
      @json.from_json(value) catch {
        _ => raise Invalid("seed must be UInt32")
      }
  }
  let count = int_option(fields, "count", 10)
  let format = text_option(fields, "format", "json")
  if !["json", "jsonl", "csv"].contains(format) {
    raise Invalid("invalid output format")
  }
  let entries = match required(fields, "columns") {
    Array(columns) => columns
    _ => raise Invalid("columns array required")
  }
  let columns = []
  for column in entries {
    columns.push(parse_column(column))
  }
  render_records(columns, records(seed, columns, count), format)
}
