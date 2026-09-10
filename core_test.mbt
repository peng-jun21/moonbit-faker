///|
test "seed repeatability" {
  assert_eq(@faker.dataset(42U, 100), @faker.dataset(42U, 100))
  assert_true(@faker.dataset(42U, 10) != @faker.dataset(43U, 10))
}

///|
test "golden seed fixture" {
  let p = @faker.dataset(20260910U, 1)[0]
  assert_eq(p.name, "郑文静")
  assert_eq(p.birth_date, "1991-02-24")
  assert_eq(p.email, "sample0@example.test")
}

///|
test "zero seed does not lock PRNG" {
  let g = @faker.Generator::new(0U)
  let xs = Array::makei(40, _ => g.integer(0, 100))
  assert_true(xs.iter().any(x => x != xs[0]))
}

///|
test "bounded range thousand samples" {
  let g = @faker.Generator::new(1U)
  for _ in 0..<10000 {
    let x = g.integer(-3, 8)
    assert_true(x >= -3 && x <= 8)
  }
  assert_eq(g.integer(7, 7), 7)
}

///|
test "invalid ranges rejected" {
  let g = @faker.Generator::new(3U)
  assert_true(
    try {
      ignore(g.integer(9, 2))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@faker.dataset(1U, 10001))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(g.date(2000, 1900))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "unique indices and reserved domains" {
  let xs = @faker.dataset(77U, 1000)
  let ids : Map[String, Bool] = Map([])
  for p in xs {
    assert_true(!ids.contains(p.id))
    ids[p.id] = true
    assert_true(p.email.has_suffix("@example.test"))
    assert_true(p.address.has_prefix("测试省"))
  }
}

///|
test "leap years and calendar bounds" {
  let g = @faker.Generator::new(2U)
  for _ in 0..<3000 {
    let d = g.date(2000, 2000)
    let parts = d.split("-").collect()
    let m = @string.parse_int(parts[1])
    let day = @string.parse_int(parts[2])
    assert_true(
      day >= 1 &&
      day <=
      (if m == 2 {
        29
      } else if m == 4 || m == 6 || m == 9 || m == 11 {
        30
      } else {
        31
      }),
    )
  }
}
