"""Independently parse real browser downloads captured by the documented UI checks."""
import csv,json,hashlib,sys
from pathlib import Path
directory=Path(sys.argv[1]);files=[directory/name for name in ['faker-20.jsonl','faker-20.csv','faker-0.csv']]
rows=[json.loads(line)for line in files[0].read_text(encoding='utf8').splitlines()]
assert len(rows)==20
for index,row in enumerate(rows):
    assert row['id']==1001+index
    assert row['sku']==row['product']['sku'] and row['price']==row['product']['price']
    assert 1<=len(row['tags'])<=3
with files[1].open(encoding='utf8',newline='')as stream:
    reader=csv.DictReader(stream);headers=reader.fieldnames;values=list(reader)
    assert len(values)==20
    for expected,actual in zip(rows,values):
        assert int(actual['id'])==expected['id'] and actual['customer']==expected['customer']
        assert json.loads(actual['product'])==expected['product'] and json.loads(actual['tags'])==expected['tags']
        assert actual['sku']==expected['sku'] and actual['price']==expected['price']
with files[2].open(encoding='utf8',newline='')as stream:
    reader=csv.DictReader(stream);assert reader.fieldnames==headers;assert list(reader)==[]
report={'scope':'Actual IAB downloads: 20 Japanese related orders JSONL and CSV; zero-row CSV header. Parsed with Python stdlib, including nested-cell equality.', 'passed':True,'files':{p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}for p in files}}
root=Path(__file__).resolve().parents[1]
(root/'evidence/browser-downloads.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8',newline='\n')
print(json.dumps(report))
