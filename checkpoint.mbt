///|
/// Includes row index, RNG, unique sets, table data and the schema contract.
pub fn Session::checkpoint(self : Session) -> Json {
  let seen : Map[String, Json] = Map([])
  for path, entries in self.seen {
    let keys = []
    for key, _ in entries {
      keys.push(key)
    }
    keys.sort_by((a, b) => a.lexical_compare(b))
    seen[path] = keys.to_json()
  }
  let result : Map[String, Json] = Map([
    ("version", (1).to_json()),
    ("schema", ToJson::to_json(self.spec)),
    ("rng", self.generator.snapshot().to_json()),
    ("index", self.index.to_json()),
    ("seen", seen.to_json()),
    ("tables", self.tables.to_json()),
  ])
  // Deep copy table values and schema arrays before handing them to the caller.
  @json.parse(result.to_json().stringify()) catch {
    _ => abort("checkpoint encoding")
  }
}

///|
/// Restore is atomic and requires the same schema. Checkpoints are not credentials.
pub fn Session::restore(
  self : Session,
  checkpoint : Json,
) -> Unit raise FakeError {
  let fields = object(checkpoint)
  reject_unknown(fields, ["version", "schema", "rng", "index", "seen", "tables"])
  if int_option(fields, "version", 0) != 1 ||
    required(fields, "schema") != ToJson::to_json(self.spec) {
    raise Invalid("checkpoint version/schema mismatch")
  }
  let state : UInt = @json.from_json(required(fields, "rng")) catch {
    _ => raise Invalid("invalid checkpoint RNG")
  }
  let index = int_option(fields, "index", -1)
  if state == 0U || index < 0 || index > 1000000000 {
    raise Invalid("checkpoint state bounds")
  }
  let seen : Map[String, Map[String, Bool]] = Map([])
  let mut count = 0
  let mut size = 0
  for path, value in object(required(fields, "seen")) {
    if !self.unique_paths.contains(path) {
      raise Invalid("unknown checkpoint unique path")
    }
    let keys : Array[String] = @json.from_json(value) catch {
      _ => raise Invalid("checkpoint unique array")
    }
    let entries : Map[String, Bool] = Map([])
    for key in keys {
      count += 1
      size += key.length()
      if count > 200000 || size > 8000000 || entries.contains(key) {
        raise Invalid("checkpoint unique budget/duplicate")
      }
      let decoded = @json.parse(key) catch {
        _ => raise Invalid("checkpoint unique encoding")
      }
      if scalar(decoded).stringify() != key {
        raise Invalid("checkpoint unique canonical value")
      }
      entries[key] = true
    }
    seen[path] = entries
  }
  let candidate = Session::new(state, self.spec)
  for name, value in object(required(fields, "tables")) {
    guard value is Array(rows) else { raise Invalid("checkpoint table array") }
    candidate.bind_table(name, rows)
  }
  self.generator.restore(state)
  self.index = index
  self.seen = seen
  self.tables = candidate.tables
  self.unique_count = count
  self.unique_text = size
}
