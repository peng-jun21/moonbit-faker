///|
/// RFC 4180 quoted CSV using the original synthetic dataset provider.
pub fn csv(seed : UInt, count : Int) -> String raise FakeError {
  let out = ["name,email,address,birth_date,id"]
  for p in dataset(seed, count) {
    out.push(
      [p.name, p.email, p.address, p.birth_date, p.id]
      .map(x => "\"" + x.replace_all(old="\"", new="\"\"") + "\"")
      .join(","),
    )
  }
  out.join("\r\n") + "\r\n"
}
