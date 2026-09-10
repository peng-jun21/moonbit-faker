///|
fn month_days(year : Int, month : Int) -> Int {
  if month == 2 {
    if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) {
      29
    } else {
      28
    }
  } else if [4, 6, 9, 11].contains(month) {
    30
  } else {
    31
  }
}

///|
fn year_start(year : Int) -> Int {
  let previous = year - 1
  365 * previous + previous / 4 - previous / 100 + previous / 400
}

///|
fn ordinal(text : String) -> Int raise FakeError {
  let cs = text.to_array()
  if cs.length() != 10 || cs[4] != '-' || cs[7] != '-' {
    raise Invalid("ISO date YYYY-MM-DD required")
  }
  for i, c in cs {
    if i != 4 && i != 7 && (c < '0' || c > '9') {
      raise Invalid("date digits")
    }
  }
  let fields = text.split("-").collect()
  let year = @string.parse_int(fields[0]) catch { _ => raise Invalid("year") }
  let month = @string.parse_int(fields[1]) catch { _ => raise Invalid("month") }
  let day = @string.parse_int(fields[2]) catch { _ => raise Invalid("day") }
  if year < 1 ||
    year > 9999 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > month_days(year, month) {
    raise Invalid("invalid calendar date")
  }
  let mut days = year_start(year) + day - 1
  for m in 1..<month {
    days += month_days(year, m)
  }
  days
}

///|
fn from_ordinal(days : Int) -> String {
  let mut lo = 1
  let mut hi = 10000
  while lo + 1 < hi {
    let mid = (lo + hi) / 2
    if year_start(mid) <= days {
      lo = mid
    } else {
      hi = mid
    }
  }
  let mut day = days - year_start(lo)
  let mut month = 1
  while day >= month_days(lo, month) {
    day -= month_days(lo, month)
    month += 1
  }
  let mut year = lo.to_string()
  while year.length() < 4 {
    year = "0" + year
  }
  year + "-" + pad(month) + "-" + pad(day + 1)
}

///|
/// Samples Gregorian calendar days in the inclusive range.
pub fn Generator::date_between(
  self : Generator,
  first : String,
  last : String,
) -> String raise FakeError {
  from_ordinal(self.integer(ordinal(first), ordinal(last)))
}
