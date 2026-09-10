///|
test "PRNG checkpoint sample and zero weights" {
  let g = @faker.Generator::new(17U)
  let state = g.snapshot()
  let first = g.uuid4()
  g.restore(state)
  assert_eq(g.uuid4(), first)
  let values = [0, 1, 2, 3, 4, 5]
  let sample = g.sample(values, 6)
  let sorted = sample.copy()
  sorted.sort()
  assert_eq(sorted, values)
  assert_eq(values, [0, 1, 2, 3, 4, 5])
  for _ in 0..<100 {
    assert_eq(g.weighted_index([0, 1, 0]), 1)
  }
  assert_true(!g.boolean(percent=0))
  assert_true(g.boolean(percent=100))
  assert_true(
    try {
      g.restore(0U)
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(g.weighted_index([0, 0]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "fixed decimal and bothify escaping" {
  let g = @faker.Generator::new(1U)
  assert_eq(g.decimal(-120, -120, 2), "-1.20")
  assert_eq(g.decimal(0, 0, 4), "0.0000")
  assert_eq(g.decimal(7, 7, 0), "7")
  assert_eq(g.bothify("\\#\\?"), "#?")
  assert_true(
    try {
      ignore(g.bothify("trailing\\"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "exact calendar bounds and Gregorian century rules" {
  let g = @faker.Generator::new(42U)
  for day in ["0001-01-01", "9999-12-31", "2000-02-29", "2024-02-29"] {
    assert_eq(g.date_between(day, day), day)
  }
  for
    date in [
      "0000-01-01", "1900-02-29", "2023-02-29", "2024-04-31", "2024-13-01", "2024-1-01",
    ] {
    assert_true(
      try {
        ignore(g.date_between(date, date))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(g.date_between("2024-02-29", "2024-02-28"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "GS1 published check digit and ISBN prefix" {
  assert_eq(@faker.ean13_from_body("629104150021"), "6291041500213")
  let g = @faker.Generator::new(6U)
  assert_true(g.isbn13().has_prefix("978"))
  for body in ["", "123", "62910415002X"] {
    assert_true(
      try {
        ignore(@faker.ean13_from_body(body))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "schema repeatability unique sequence nullable and weighted choice" {
  let columns = [
    @faker.Column::new("id", Sequence(100, 2), unique=true),
    @faker.Column::new("uuid", Uuid4, unique=true),
    @faker.Column::new("tier", WeightedChoice(["unused", "active"], [0, 5])),
    @faker.Column::new("empty", Name, null_percent=100),
  ]
  let rows = @faker.records(42U, columns, 50)
  assert_eq(rows, @faker.records(42U, columns, 50))
  let text = @faker.render_records(columns, rows, "json")
  assert_true(text.contains("\"tier\":\"active\""))
  assert_true(text.contains("\"empty\":null"))
  assert_true(text.contains("\"id\":198"))
}

///|
test "unique retry and schema dimension failures are explicit" {
  assert_true(
    try {
      ignore(
        @faker.records(
          1U,
          [@faker.Column::new("x", Constant(Json::string("one")), unique=true)],
          2,
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @faker.records(
          1U,
          [@faker.Column::new("x", Name, unique=true, null_percent=100)],
          2,
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @faker.records(
          1U,
          [@faker.Column::new("x", Name), @faker.Column::new("x", Name)],
          1,
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @faker.records(
          1U,
          [@faker.Column::new("x", Sequence(1000000000, 1))],
          2,
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "CSV escapes scalar text and zero rows keep headers" {
  let columns = [
    @faker.Column::new("quoted,name", Constant(Json::string("a,\"b\"\r\nc"))),
    @faker.Column::new("nullable", Constant(Json::null())),
  ]
  let rows = @faker.records(0U, columns, 1)
  assert_eq(
    @faker.render_records(columns, rows, "csv"),
    "\"quoted,name\",\"nullable\"\r\n\"a,\"\"b\"\"\r\nc\",\"\"\r\n",
  )
  assert_eq(
    @faker.render_records(columns, [], "csv"),
    "\"quoted,name\",\"nullable\"\r\n",
  )
  assert_eq(@faker.render_records(columns, [], "jsonl"), "")
}

///|
test "JSON request rejects bad configuration before generating" {
  assert_eq(
    @faker.generate_request(
      "{\"count\":2,\"columns\":[{\"name\":\"id\",\"provider\":\"sequence\",\"start\":1}],\"format\":\"jsonl\"}",
    ),
    "{\"id\":1}\n{\"id\":2}\n",
  )
  for
    request in [
      "{}", "{\"seed\":-1,\"columns\":[]}", "{\"count\":1.5,\"columns\":[]}", "{\"columns\":[{\"name\":\"x\",\"provider\":\"name\",\"min\":2}]}",
      "{\"columns\":[{\"name\":\"x\",\"provider\":\"constant\",\"value\":[]}]}",
    ] {
    assert_true(
      try {
        ignore(@faker.generate_request(request))
        false
      } catch {
        _ => true
      },
    )
  }
}
