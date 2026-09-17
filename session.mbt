///|
pub struct Session {
  generator : Generator
  spec : Spec
  unique_paths : Map[String, Bool]
  mut seen : Map[String, Map[String, Bool]]
  mut tables : Map[String, Array[Json]]
  mut index : Int
  mut unique_count : Int
  mut unique_text : Int
}

///|
priv struct RowContext {
  published : Map[String, Json]
  pending : Map[String, Map[String, Bool]]
  mut visits : Int
  mut text : Int
  mut unique_count : Int
  mut unique_text : Int
}

///|
pub fn Session::new(seed : UInt, spec : Spec) -> Session raise FakeError {
  let unique_paths : Map[String, Bool] = Map([])
  validate_spec(spec, "", 0, unique_paths, Ref(0))
  {
    generator: Generator::new(seed),
    spec: owned_spec(spec),
    unique_paths,
    seen: Map([]),
    tables: Map([]),
    index: 0,
    unique_count: 0,
    unique_text: 0,
  }
}

///|
pub fn Session::position(self : Session) -> Int {
  self.index
}

///|
fn checked_json(
  value : Json,
  depth : Int,
  nodes : Ref[Int],
  text : Ref[Int],
) -> Unit raise FakeError {
  nodes.val += 1
  if depth > 16 || nodes.val > 200000 || text.val > 8000000 {
    raise Invalid("JSON value budget")
  }
  match value {
    String(s) => text.val += s.length()
    Number(n, ..) =>
      if n.is_nan() || n.is_inf() {
        raise Invalid("non-finite JSON value")
      }
    Object(fields) =>
      for key, child in fields {
        text.val += key.length()
        checked_json(child, depth + 1, nodes, text)
      }
    Array(values) =>
      for child in values {
        checked_json(child, depth + 1, nodes, text)
      }
    _ => ()
  }
  if text.val > 8000000 {
    raise Invalid("JSON text budget")
  }
}

///|
pub fn Session::bind_table(
  self : Session,
  name : String,
  rows : Array[Json],
) -> Unit raise FakeError {
  if name.is_empty() ||
    name.length() > 80 ||
    rows.is_empty() ||
    rows.length() > 50000 ||
    (!self.tables.contains(name) && self.tables.length() >= 16) {
    raise Invalid("table dimensions")
  }
  let nodes = Ref(0)
  let text = Ref(0)
  for existing_name, existing in self.tables {
    if existing_name != name {
      for row in existing {
        checked_json(row, 0, nodes, text)
      }
    }
  }
  for row in rows {
    checked_json(row, 0, nodes, text)
  }
  // Store an owned copy so external mutation cannot change a running session.
  self.tables[name] = rows.map(row => {
    @json.parse(row.stringify()) catch {
      _ => raise Invalid("table copy failed")
    }
  })
}

///|
fn Session::evaluate(
  self : Session,
  spec : Spec,
  schema_path : String,
  value_path : String,
  context : RowContext,
) -> Json raise FakeError {
  context.visits += 1
  if context.visits > 100000 {
    raise Invalid("row generation work budget")
  }
  let value = match spec {
    Value(provider) => self.generator.provide(provider, self.index)
    Object(fields) => {
      let object : Map[String, Json] = Map([])
      for i, (name, child) in fields {
        object[name] = self.evaluate(
          child,
          schema_path + "/" + i.to_string(),
          value_path + "/" + pointer_escape(name),
          context,
        )
      }
      object.to_json()
    }
    List(child, low, high) => {
      let count = self.generator.integer(low, high)
      Array::makei(count, i => {
        self.evaluate(
          child,
          schema_path + "/items",
          value_path + "/" + i.to_string(),
          context,
        )
      }).to_json()
    }
    Nullable(child, percent) =>
      if self.generator.boolean(percent~) {
        Json::null()
      } else {
        self.evaluate(child, schema_path + "/nullable", value_path, context)
      }
    Unique(child) => {
      let committed = self.seen.get(schema_path).unwrap_or(Map([]))
      let pending = context.pending.get(schema_path).unwrap_or(Map([]))
      let mut accepted = None
      for _ in 0..<1000 {
        let candidate = self.evaluate(
          child,
          schema_path + "/unique",
          value_path,
          context,
        )
        let key = candidate.stringify()
        if committed.contains(key) || pending.contains(key) {
          continue
        }
        pending[key] = true
        context.pending[schema_path] = pending
        context.unique_count += 1
        context.unique_text += key.length()
        if self.unique_count + context.unique_count > 200000 ||
          self.unique_text + context.unique_text > 8000000 {
          raise Invalid("session uniqueness storage budget")
        }
        accepted = Some(candidate)
        break
      }
      match accepted {
        Some(value) => value
        None => raise Invalid("unique retry budget at " + value_path)
      }
    }
    Reference(pointer) => resolve_reference(context.published, pointer)
    Foreign(name, pointer) => {
      guard self.tables.get(name) is Some(rows) else {
        raise Invalid("unbound foreign table: " + name)
      }
      let selected = at_pointer(
        self.generator.choose(rows),
        pointer_parts(pointer)[:],
      )
      @json.parse(selected.stringify()) catch {
        _ => raise Invalid("foreign value copy")
      }
    }
    Join(parts, separator) => {
      let strings = []
      for i, child in parts {
        let value = self.evaluate(
          child,
          schema_path + "/join" + i.to_string(),
          value_path + "/@join" + i.to_string(),
          context,
        )
        strings.push(
          match value {
            String(s) => s
            Null => ""
            Number(_, ..) | True | False => value.stringify()
            _ => raise Invalid("join requires scalar values")
          },
        )
      }
      Json::string(strings.join(separator))
    }
  }
  if value is String(s) {
    context.text += s.length()
  }
  if context.text > 1000000 {
    raise Invalid("row text budget")
  }
  context.published[value_path] = value
  value
}

///|
/// Each row commits atomically. On failure, RNG, position and uniqueness remain unchanged.
pub fn Session::next(self : Session) -> Json raise FakeError {
  if self.index >= 1000000000 {
    raise Invalid("session row position limit")
  }
  let state = self.generator.snapshot()
  let context : RowContext = {
    published: Map([]),
    pending: Map([]),
    visits: 0,
    text: 0,
    unique_count: 0,
    unique_text: 0,
  }
  let row = {
    errdefer {
      self.generator.state = state
    }
    let value = self.evaluate(self.spec, "", "", context)
    if value.stringify().length() > 1000000 {
      raise Invalid("serialized row budget")
    }
    value
  }
  for path, entries in context.pending {
    let target = self.seen.get(path).unwrap_or(Map([]))
    for key, _ in entries {
      target[key] = true
    }
    self.seen[path] = target
  }
  self.unique_count += context.unique_count
  self.unique_text += context.unique_text
  self.index += 1
  row
}
