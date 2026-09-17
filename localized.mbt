///|
priv struct LocaleTable {
  values : Array[String]
  cumulative : Array[Double]
  weighted : Bool
  mode : String
}

///|
fn load_locales() -> Map[String, Map[String, LocaleTable]] {
  let result : Map[String, Map[String, LocaleTable]] = Map([])
  try {
    let data = object(@json.parse(locale_source))
    for locale, entries in data {
      let tables : Map[String, LocaleTable] = Map([])
      for provider_name, entry in object(entries) {
        let fields = object(entry)
        let values : Array[String] = @json.from_json(required(fields, "values"))
        let weights : Array[Double] = @json.from_json(
          required(fields, "weights"),
        )
        let cumulative = []
        let mut sum = 0.0
        for weight in weights {
          sum += weight
          cumulative.push(sum)
        }
        tables[provider_name] = {
          values,
          cumulative,
          weighted: required(fields, "weighted") == true.to_json(),
          mode: text_option(fields, "mode", "literal"),
        }
      }
      result[locale] = tables
    }
  } catch {
    _ => abort("invalid bundled locale data")
  }
  result
}

///|
let locale_tables : Map[String, Map[String, LocaleTable]] = load_locales()

///|
fn locale_table(
  locale : String,
  provider_name : String,
) -> LocaleTable raise FakeError {
  guard locale_tables.get(locale) is Some(tables) else {
    raise Invalid("unknown locale: " + locale)
  }
  guard tables.get(provider_name) is Some(table) else {
    raise Invalid(
      "unsupported localized provider: " + locale + "/" + provider_name,
    )
  }
  table
}

///|
pub fn locales() -> Array[String] {
  ["en_US", "zh_CN", "en_GB", "de_DE", "fr_FR", "ja_JP"]
}

///|
pub fn locale_methods(locale : String) -> Array[String] raise FakeError {
  guard locale_tables.get(locale) is Some(tables) else {
    raise Invalid("unknown locale: " + locale)
  }
  let names = []
  for name, _ in tables {
    if !name.has_prefix("postcode_set_") {
      names.push(name)
    }
  }
  names.sort_by((a, b) => a.lexical_compare(b))
  names
}

///|
/// A copy of the attributed source values/templates, useful for data inspection.
pub fn locale_values(
  locale : String,
  provider_name : String,
) -> Array[String] raise FakeError {
  locale_table(locale, provider_name).values.copy()
}

///|
fn Generator::locale_pick(
  self : Generator,
  table : LocaleTable,
) -> String raise FakeError {
  if !table.weighted {
    return self.choose(table.values)
  }
  let draw = self.next().to_double() /
    4294967296.0 *
    table.cumulative[table.cumulative.length() - 1]
  let mut low = 0
  let mut high = table.cumulative.length() - 1
  while low < high {
    let middle = (low + high) / 2
    if draw < table.cumulative[middle] {
      high = middle
    } else {
      low = middle + 1
    }
  }
  table.values[low]
}

///|
fn Generator::locale_symbols(
  self : Generator,
  pattern : String,
) -> String raise FakeError {
  let mut text = pattern
  // Faker numerify processes each placeholder kind in this order, then lexify.
  for symbol in ['#', '%', '$', '!', '@', '?'] {
    let out = StringBuilder()
    for c in text {
      if c != symbol {
        out.write_char(c)
        continue
      }
      let replacement = match symbol {
        '#' => self.integer(0, 9).to_string()
        '%' => self.integer(1, 9).to_string()
        '$' => self.integer(2, 9).to_string()
        '!' =>
          if self.integer(0, 1) == 0 {
            ""
          } else {
            self.integer(0, 9).to_string()
          }
        '@' =>
          if self.integer(0, 1) == 0 {
            ""
          } else {
            self.integer(1, 9).to_string()
          }
        _ =>
          "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".to_array()[self.integer(
            0, 51,
          )].to_string()
      }
      out.write_string(replacement)
    }
    text = out.to_string()
  }
  text
}

///|
fn Generator::localized_inner(
  self : Generator,
  locale : String,
  provider_name : String,
  depth : Int,
) -> String raise FakeError {
  if depth > 16 {
    raise Invalid("locale expansion depth")
  }
  let table = locale_table(locale, provider_name)
  if table.mode == "us_postcode" {
    let mut code = self.integer(501, 99950).to_string()
    while code.length() < 5 {
      code = "0" + code
    }
    return code
  }
  if table.mode == "jp_postcode" {
    let mut first = self.integer(0, 999).to_string()
    let mut last = self.integer(0, 9999).to_string()
    while first.length() < 3 {
      first = "0" + first
    }
    while last.length() < 4 {
      last = "0" + last
    }
    return first + "-" + last
  }
  let selected = if table.mode == "fixed_template" {
    table.values[0]
  } else {
    self.locale_pick(table)
  }
  if table.mode == "fr_postcode" {
    let department = if selected == "2A" || selected == "2B" {
      "20"
    } else {
      selected
    }
    return department +
      (if department.length() == 2 {
        self.integer(100, 999)
      } else {
        self.integer(10, 99)
      }).to_string()
  }
  if table.mode == "literal" {
    return selected
  }
  if table.mode == "delegate" {
    return self.localized_inner(locale, selected, depth + 1)
  }
  if table.mode == "gb_postcode" {
    let out = StringBuilder()
    for c in selected {
      out.write_string(
        self.locale_pick(locale_table(locale, "postcode_set_" + c.to_string())),
      )
    }
    return out.to_string()
  }
  let cs = selected.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < cs.length() {
    if i + 1 < cs.length() && cs[i] == '{' && cs[i + 1] == '{' {
      i += 2
      let token = StringBuilder()
      while i + 1 < cs.length() && !(cs[i] == '}' && cs[i + 1] == '}') {
        token.write_char(cs[i])
        i += 1
      }
      if i + 1 >= cs.length() {
        raise Invalid("unclosed locale token")
      }
      out.write_string(
        self.localized_inner(locale, token.to_string(), depth + 1),
      )
      i += 2
    } else {
      out.write_char(cs[i])
      i += 1
    }
  }
  let expanded = out.to_string()
  if expanded.length() > 4096 {
    raise Invalid("locale output length")
  }
  self.locale_symbols(expanded)
}

///|
/// Locale-aware attributed provider data; the PRNG is local, not Python MT19937.
pub fn Generator::localized(
  self : Generator,
  locale : String,
  provider_name : String,
) -> String raise FakeError {
  if provider_name.has_prefix("postcode_set_") {
    raise Invalid("internal locale table")
  }
  self.localized_inner(locale, provider_name, 0)
}
