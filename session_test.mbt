///|
test "nested rows keep coherent references foreign keys and checkpoints" {
  let request =
    #|{"seed":71,"tables":{"products":[{"sku":"A","price":100},{"sku":"B","price":200}]},"schema":{"type":"object","fields":[{"name":"id","provider":"sequence","start":1,"unique":true},{"name":"customer","type":"object","fields":[{"name":"first","provider":"localized","locale":"fr_FR","method":"first_name"},{"name":"label","type":"join","parts":[{"type":"ref","path":"/customer/first"},{"provider":"constant","value":"-sample"}]}]},{"name":"items","type":"array","min":2,"max":4,"items":{"type":"foreign","table":"products","path":""}},{"name":"first_sku","type":"ref","path":"/items/0/sku"}]}}
  let session = @faker.open_session(request)
  for index in 1..<=7 {
    let row = session.next()
    guard row is Object(fields) else { fail("object") }
    assert_eq(fields["id"], index.to_json())
    guard fields["customer"] is Object(customer) else { fail("customer") }
    guard customer["first"] is String(first) else { fail("first") }
    assert_eq(customer["label"], Json::string(first + "-sample"))
    guard fields["items"] is Array(items) else { fail("items") }
    assert_true(items.length() >= 2 && items.length() <= 4)
    guard items[0] is Object(item) else { fail("item") }
    assert_eq(fields["first_sku"], item["sku"])
  }
  let checkpoint = session.checkpoint()
  let resumed = @faker.open_session(request)
  resumed.restore(checkpoint)
  for _ in 0..<50 {
    assert_eq(session.next(), resumed.next())
  }
  assert_eq(session.position(), 57)
}

///|
test "failed rows and invalid restores preserve all state" {
  let session = @faker.Session::new(8U, Unique(Value(Choice(["only"]))))
  assert_eq(session.next(), Json::string("only"))
  let checkpoint = session.checkpoint()
  let failed = try {
    ignore(session.next())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(session.checkpoint(), checkpoint)
  let bad = @json.parse("{\"version\":99}")
  assert_true(
    try {
      session.restore(bad)
      false
    } catch {
      _ => true
    },
  )
  assert_eq(session.checkpoint(), checkpoint)
  let unresolved = @faker.Session::new(
    99U,
    Object([("random", Value(Uuid4)), ("bad", Reference("/future"))]),
  )
  let before = unresolved.checkpoint()
  assert_true(
    try {
      ignore(unresolved.next())
      false
    } catch {
      _ => true
    },
  )
  assert_eq(before, unresolved.checkpoint())
}

///|
test "session owns schema tables and emitted foreign objects" {
  let choices = ["a", "b"]
  let session = @faker.Session::new(1U, Value(Choice(choices)))
  choices[0] = "corrupted"
  choices[1] = "corrupted"
  for _ in 0..<10 {
    assert_true(session.next() != Json::string("corrupted"))
  }
  let row : Map[String, Json] = Map([("id", (1).to_json())])
  let foreign = @faker.Session::new(2U, Foreign("t", ""))
  foreign.bind_table("t", [row.to_json()])
  row["id"] = (999).to_json()
  guard foreign.next() is Object(emitted) else { fail("foreign object") }
  assert_eq(emitted["id"], (1).to_json())
  emitted["id"] = (42).to_json()
  guard foreign.next() is Object(again) else { fail("foreign object") }
  assert_eq(again["id"], (1).to_json())
}

///|
test "pointer escaping unique array scope and session JSON lifecycle" {
  let spec = @faker.Spec::Object([
    ("a/b", Object([("~key", Value(Constant((7).to_json())))])),
    ("copy", Reference("/a~1b/~0key")),
  ])
  guard @faker.Session::new(1U, spec).next() is Object(row) else { fail("row") }
  assert_eq(row["copy"], (7).to_json())
  let unique = @faker.Session::new(
    2U,
    List(Unique(Value(Choice(["a", "b"]))), 2, 2),
  )
  guard unique.next() is Array(values) else { fail("array") }
  assert_true(values[0] != values[1])
  assert_true(
    try {
      ignore(unique.next())
      false
    } catch {
      _ => true
    },
  )
  assert_eq(unique.position(), 1)
  let opened = @json.parse(
    @faker.session_request(
      "{\"op\":\"open\",\"definition\":{\"schema\":{\"provider\":\"sequence\"}}}",
    ),
  )
  guard opened is Object(fields) else { fail("open") }
  let command : Map[String, Json] = Map([
    ("op", Json::string("next")),
    ("id", fields["id"]),
  ])
  guard @json.parse(@faker.session_request(command.to_json().stringify()))
    is Object(first) else {
    fail("next")
  }
  assert_eq(first["row"], (0).to_json())
  command["checkpoint"] = Json::null()
  guard @json.parse(@faker.session_request(command.to_json().stringify()))
    is Object(invalid) else {
    fail("invalid command")
  }
  assert_eq(invalid["ok"], false.to_json())
  command.remove("checkpoint")
  guard @json.parse(@faker.session_request(command.to_json().stringify()))
    is Object(second) else {
    fail("second")
  }
  assert_eq(second["row"], (1).to_json())
  command["op"] = Json::string("close")
  ignore(@faker.session_request(command.to_json().stringify()))
  command["op"] = Json::string("next")
  guard @json.parse(@faker.session_request(command.to_json().stringify()))
    is Object(closed) else {
    fail("close")
  }
  assert_eq(closed["ok"], false.to_json())
}

///|
test "every bundled localized method produces deterministic bounded text" {
  for locale in @faker.locales() {
    for provider_name in @faker.locale_methods(locale) {
      let a = @faker.Generator::new(1234U)
      let b = @faker.Generator::new(1234U)
      for _ in 0..<3 {
        let value = a.localized(locale, provider_name)
        assert_eq(value, b.localized(locale, provider_name))
        assert_true(value.length() <= 4096)
        assert_true(!value.contains("{{"))
      }
    }
  }
  let copy = @faker.locale_values("zh_CN", "first_name")
  copy[0] = "changed"
  assert_true(@faker.locale_values("zh_CN", "first_name")[0] != "changed")
  assert_true(
    try {
      ignore(@faker.Generator::new(1U).localized("unknown", "name"))
      false
    } catch {
      _ => true
    },
  )
}
