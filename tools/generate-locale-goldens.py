import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
report=json.loads((root/'evidence/locale-comparison.json').read_text(encoding='utf8'))
assert report['mismatches']==0
lines=['// Generated from independent Faker provider output, not local actual values.','///|','test "official locale provider golden vectors with controlled RNG" {','  let fixtures : Array[(String, String, UInt, Array[String])] = [']
for row in report['rows']:
    values=row['reference']['values']
    lines.append('    ('+json.dumps(row['locale'])+', '+json.dumps(row['method'])+', '+str(row['seed'])+'U, '+json.dumps(values,ensure_ascii=False)+'),')
lines.extend(['  ]','  for (locale, provider_name, seed, expected) in fixtures {','    let generator = @faker.Generator::new(seed)','    for value in expected { assert_eq(generator.localized(locale, provider_name), value) }','  }','}'])
(root/'locale_golden_test.mbt').write_text('\n'.join(lines)+'\n',encoding='utf8',newline='\n')
print(len(report['rows']),'official golden cases')
