///|
pub(all) enum Spec {
  Value(Provider)
  Object(Array[(String, Spec)])
  List(Spec, Int, Int)
  Nullable(Spec, Int)
  Unique(Spec)
  Reference(String)
  Foreign(String, String)
  Join(Array[Spec], String)
} derive(Debug, Eq, ToJson)

///|
fn scalar_spec(spec : Spec) -> Bool {
  match spec {
    Value(_) => true
    Nullable(child, _) => scalar_spec(child)
    _ => false
  }
}

///|
fn validate_spec(
  spec : Spec,
  path : String,
  depth : Int,
  unique_paths : Map[String, Bool],
  counter : Ref[Int],
) -> Unit raise FakeError {
  counter.val += 1
  if depth > 16 || counter.val > 1024 {
    raise Invalid("schema depth/node limit")
  }
  match spec {
    Value(provider) => provider.validate()
    Object(fields) => {
      if fields.length() > 128 {
        raise Invalid("object field limit")
      }
      let names : Map[String, Bool] = Map([])
      for i, (name, child) in fields {
        if name.is_empty() || name.length() > 80 || names.contains(name) {
          raise Invalid("invalid or duplicate field: " + name)
        }
        names[name] = true
        validate_spec(
          child,
          path + "/" + i.to_string(),
          depth + 1,
          unique_paths,
          counter,
        )
      }
    }
    List(child, low, high) => {
      if low < 0 || low > high || high > 1000 {
        raise Invalid("array length 0..1000 required")
      }
      validate_spec(child, path + "/items", depth + 1, unique_paths, counter)
    }
    Nullable(child, percent) => {
      if percent < 0 || percent > 100 {
        raise Invalid("null percentage")
      }
      validate_spec(child, path + "/nullable", depth + 1, unique_paths, counter)
    }
    Unique(child) => {
      if !scalar_spec(child) {
        raise Invalid("unique requires a scalar provider, optionally nullable")
      }
      unique_paths[path] = true
      validate_spec(child, path + "/unique", depth + 1, unique_paths, counter)
    }
    Reference(pointer) => ignore(pointer_parts(pointer))
    Foreign(table, pointer) => {
      if table.is_empty() || table.length() > 80 {
        raise Invalid("invalid table name")
      }
      ignore(pointer_parts(pointer))
    }
    Join(parts, separator) => {
      if parts.length() > 128 || separator.length() > 1024 {
        raise Invalid("join dimensions")
      }
      for i, child in parts {
        validate_spec(
          child,
          path + "/join" + i.to_string(),
          depth + 1,
          unique_paths,
          counter,
        )
      }
    }
  }
}

///|
fn pointer_parts(pointer : String) -> Array[String] raise FakeError {
  if pointer.length() > 1024 ||
    (!pointer.is_empty() && !pointer.has_prefix("/")) {
    raise Invalid("reference must be a JSON pointer")
  }
  if pointer.is_empty() {
    return []
  }
  let parts = []
  for fragment in pointer[1:].split("/") {
    let cs = fragment.to_owned().to_array()
    let out = StringBuilder()
    let mut i = 0
    while i < cs.length() {
      if cs[i] == '~' {
        if i + 1 >= cs.length() || (cs[i + 1] != '0' && cs[i + 1] != '1') {
          raise Invalid("invalid JSON pointer escape")
        }
        out.write_char(if cs[i + 1] == '0' { '~' } else { '/' })
        i += 2
      } else {
        out.write_char(cs[i])
        i += 1
      }
    }
    parts.push(out.to_string())
  }
  parts
}

///|
fn pointer_escape(text : String) -> String {
  text.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn at_pointer(value : Json, parts : ArrayView[String]) -> Json raise FakeError {
  let mut current = value
  for part in parts {
    current = match current {
      Object(fields) =>
        match fields.get(part) {
          Some(v) => v
          None => raise Invalid("reference field missing: " + part)
        }
      Array(values) => {
        let mut index = 0
        if part.is_empty() || (part.length() > 1 && part.has_prefix("0")) {
          raise Invalid("invalid reference index")
        }
        for c in part {
          if c < '0' || c > '9' || index > 1000000 {
            raise Invalid("invalid reference index")
          }
          index = index * 10 + c.to_int() - 48
        }
        match values.get(index) {
          Some(v) => v
          None => raise Invalid("reference index out of range")
        }
      }
      _ => raise Invalid("reference traverses a scalar")
    }
  }
  current
}

///|
fn resolve_reference(
  published : Map[String, Json],
  pointer : String,
) -> Json raise FakeError {
  if published.get(pointer) is Some(value) {
    return value
  }
  let parts = pointer_parts(pointer)
  let mut path = ""
  for i, part in parts {
    path += "/" + pointer_escape(part)
    if published.get(path) is Some(value) {
      return at_pointer(value, parts[i + 1:])
    }
  }
  raise Invalid("reference requires an earlier completed field: " + pointer)
}

///|
fn parse_spec_inner(value : Json, depth : Int) -> Spec raise FakeError {
  if depth > 16 {
    raise Invalid("schema depth limit")
  }
  let fields = object(value)
  if fields.contains("provider") {
    let column = parse_column(value)
    let mut spec = Value(column.provider)
    if column.null_percent != 0 {
      spec = Nullable(spec, column.null_percent)
    }
    if column.unique {
      spec = Unique(spec)
    }
    return spec
  }
  let kind = text_option(fields, "type", "")
  match kind {
    "object" => {
      reject_unknown(fields, ["type", "fields", "name"])
      guard required(fields, "fields") is Array(entries) else {
        raise Invalid("fields array required")
      }
      if entries.length() > 128 {
        raise Invalid("object field limit")
      }
      Object(
        entries.map(entry => {
          let field = object(entry)
          (text_option(field, "name", ""), parse_spec_inner(entry, depth + 1))
        }),
      )
    }
    "array" => {
      reject_unknown(fields, ["type", "items", "min", "max", "name"])
      List(
        parse_spec_inner(required(fields, "items"), depth + 1),
        int_option(fields, "min", 0),
        int_option(fields, "max", 3),
      )
    }
    "ref" => {
      reject_unknown(fields, ["type", "path", "name"])
      Reference(text_option(fields, "path", ""))
    }
    "foreign" => {
      reject_unknown(fields, ["type", "table", "path", "name"])
      Foreign(text_option(fields, "table", ""), text_option(fields, "path", ""))
    }
    "nullable" => {
      reject_unknown(fields, ["type", "value", "percent", "name"])
      Nullable(
        parse_spec_inner(required(fields, "value"), depth + 1),
        int_option(fields, "percent", 50),
      )
    }
    "unique" => {
      reject_unknown(fields, ["type", "value", "name"])
      Unique(parse_spec_inner(required(fields, "value"), depth + 1))
    }
    "join" => {
      reject_unknown(fields, ["type", "parts", "separator", "name"])
      guard required(fields, "parts") is Array(parts) else {
        raise Invalid("join parts array required")
      }
      if parts.length() > 128 {
        raise Invalid("join part limit")
      }
      Join(
        parts.map(p => parse_spec_inner(p, depth + 1)),
        text_option(fields, "separator", ""),
      )
    }
    _ => raise Invalid("unknown schema type: " + kind)
  }
}

///|
pub fn parse_spec(value : Json) -> Spec raise FakeError {
  let spec = parse_spec_inner(value, 0)
  validate_spec(spec, "", 0, Map([]), Ref(0))
  spec
}

///|
fn owned_spec(spec : Spec) -> Spec {
  match spec {
    Value(Choice(values)) => Value(Choice(values.copy()))
    Value(WeightedChoice(values, weights)) =>
      Value(WeightedChoice(values.copy(), weights.copy()))
    Object(fields) => Object(fields.map(pair => (pair.0, owned_spec(pair.1))))
    List(child, low, high) => List(owned_spec(child), low, high)
    Nullable(child, percent) => Nullable(owned_spec(child), percent)
    Unique(child) => Unique(owned_spec(child))
    Join(parts, separator) => Join(parts.map(owned_spec), separator)
    other => other
  }
}
