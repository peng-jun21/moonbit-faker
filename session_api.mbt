///|
fn request_seed(fields : Map[String, Json]) -> UInt raise FakeError {
  match fields.get("seed") {
    None => 0U
    Some(value) =>
      @json.from_json(value) catch {
        _ => raise Invalid("seed must be UInt32")
      }
  }
}

///|
fn session_from_fields(fields : Map[String, Json]) -> Session raise FakeError {
  let spec = if fields.get("schema") is Some(value) {
    parse_spec(value)
  } else {
    guard required(fields, "columns") is Array(entries) else {
      raise Invalid("columns array required")
    }
    let value : Map[String, Json] = Map([
      ("type", Json::string("object")),
      ("fields", entries.to_json()),
    ])
    parse_spec(value.to_json())
  }
  let session = Session::new(request_seed(fields), spec)
  if fields.get("tables") is Some(value) {
    for name, rows in object(value) {
      guard rows is Array(entries) else {
        raise Invalid("table rows array required")
      }
      session.bind_table(name, entries)
    }
  }
  if fields.get("checkpoint") is Some(value) {
    session.restore(value)
  }
  session
}

///|
/// Parse a schema/columns session definition, optionally with bound tables and checkpoint.
pub fn open_session(request : String) -> Session raise FakeError {
  if request.length() > 16000000 {
    raise Invalid("session request length")
  }
  let fields = object(
    @json.parse(request) catch {
      _ => raise Invalid("invalid session JSON")
    },
  )
  reject_unknown(fields, ["seed", "schema", "columns", "tables", "checkpoint"])
  if fields.contains("schema") && fields.contains("columns") {
    raise Invalid("use schema or columns")
  }
  session_from_fields(fields)
}

///|
let sessions : Map[Int, Session] = Map([])

///|
let next_session_id : Ref[Int] = Ref(1)

///|
fn session_json(fields : Array[(String, Json)]) -> String {
  let result : Map[String, Json] = Map(fields)
  result["ok"] = true.to_json()
  result.to_json().stringify()
}

///|
/// Thin stateful JSON bridge for JS hosts. Explicit close releases the session.
pub fn session_request(input : String) -> String {
  try {
    if input.length() > 16000000 {
      raise Invalid("session command length")
    }
    let fields = object(@json.parse(input))
    let operation = text_option(fields, "op", "")
    if operation == "catalog" {
      reject_unknown(fields, ["op"])
      let catalog : Map[String, Json] = Map([])
      for locale in locales() {
        catalog[locale] = locale_methods(locale).to_json()
      }
      return session_json([("locales", catalog.to_json())])
    }
    if operation == "open" {
      reject_unknown(fields, ["op", "definition"])
      if sessions.length() >= 16 || next_session_id.val >= 1000000000 {
        raise Invalid("active session limit")
      }
      let session = open_session(required(fields, "definition").stringify())
      let id = next_session_id.val
      next_session_id.val += 1
      sessions[id] = session
      return session_json([
        ("id", id.to_json()),
        ("index", session.position().to_json()),
      ])
    }
    if operation == "restore" {
      reject_unknown(fields, ["op", "id", "checkpoint"])
    } else {
      reject_unknown(fields, ["op", "id"])
    }
    let id = int_option(fields, "id", 0)
    guard sessions.get(id) is Some(session) else {
      raise Invalid("unknown session")
    }
    match operation {
      "next" => {
        let row = session.next()
        session_json([("row", row), ("index", session.position().to_json())])
      }
      "checkpoint" => session_json([("checkpoint", session.checkpoint())])
      "restore" => {
        session.restore(required(fields, "checkpoint"))
        session_json([("index", session.position().to_json())])
      }
      "close" => {
        sessions.remove(id)
        session_json([])
      }
      _ => raise Invalid("unknown session operation")
    }
  } catch {
    error => {
      let result : Map[String, Json] = Map([
        ("ok", false.to_json()),
        ("error", Json::string(Repr(error).to_string())),
      ])
      result.to_json().stringify()
    }
  }
}
