///|
pub fn run(input : String) -> String {
  try {
    if input.trim().has_prefix("{") {
      return @lib.generate_request(input)
    }
    let p = input.trim().split(" ").filter(s => !s.is_empty()).collect()
    if p.length() != 2 {
      return "ERROR: seed count"
    }
    Repr(
      @lib.dataset(
        @strconv.parse_uint(p[0].to_owned()),
        @strconv.parse_int(p[1].to_owned()),
      ),
    ).to_string()
  } catch {
    e => "ERROR: " + Repr(e).to_string()
  }
}

///|
fn main {

}
