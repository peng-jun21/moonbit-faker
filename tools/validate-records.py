"""Independent stdlib validation of already generated files. No MoonBit calls."""
import csv, datetime, decimal, hashlib, ipaddress, json, pathlib, platform, re, urllib.parse, uuid
root=pathlib.Path(__file__).resolve().parent.parent
folder=root/'evidence'
rows=json.loads((folder/'records.json').read_text(encoding='utf-8'))
schema=json.loads((folder/'records-schema.json').read_text(encoding='utf-8'))
assert len(rows)==schema['count']==256
assert rows==[json.loads(line) for line in (folder/'records.jsonl').read_text(encoding='utf-8').splitlines()]
with (folder/'records.csv').open(encoding='utf-8',newline='') as file:
    reader=csv.DictReader(file)
    assert reader.fieldnames==[c['name'] for c in schema['columns']]
    csv_rows=list(reader)
assert len(csv_rows)==len(rows)
def text(value):
    if value is None:return ''
    if isinstance(value,bool):return str(value).lower()
    return str(value)
assert csv_rows==[{key:text(value) for key,value in row.items()} for row in rows]
networks=[ipaddress.ip_network(n) for n in ('192.0.2.0/24','198.51.100.0/24','203.0.113.0/24')]
ipv6=ipaddress.ip_network('2001:db8::/32')
identifiers=set()
for i,row in enumerate(rows):
    assert row['id']==1000+2*i
    parsed=uuid.UUID(row['uuid'])
    assert parsed.version==4 and parsed.variant==uuid.RFC_4122
    assert parsed not in identifiers
    identifiers.add(parsed)
    assert any(ipaddress.ip_address(row['ipv4']) in n for n in networks)
    assert ipaddress.ip_address(row['ipv6']) in ipv6
    assert re.fullmatch(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}',row['mac'])
    assert int(row['mac'][:2],16)&3==2
    assert re.fullmatch(r'#[0-9a-f]{6}',row['color'])
    assert re.fullmatch(r'user_[a-z]{12}',row['username'])
    assert re.fullmatch(r'user_[a-z]{12}@example\.test',row['email'])
    url=urllib.parse.urlsplit(row['url'])
    assert url.scheme=='https' and re.fullmatch(r'sample-[a-z]{8}\.example\.test',url.hostname)
    assert datetime.date(2024,2,28)<=datetime.date.fromisoformat(row['date'])<=datetime.date(2024,3,2)
    assert re.fullmatch(r'-?\d+\.\d{2}',row['price'])
    assert decimal.Decimal('-125.00')<=decimal.Decimal(row['price'])<=decimal.Decimal('300.00')
    assert isinstance(row['active'],bool) and isinstance(row['quantity'],int) and 1<=row['quantity']<=9
    for key in ('ean','isbn'):
        number=row[key]
        assert re.fullmatch(r'\d{13}',number)
        assert sum(int(d)*(1 if j%2==0 else 3) for j,d in enumerate(number))%10==0
    assert row['isbn'].startswith('978')
    assert re.fullmatch(r'SKU-[a-z]{2}-\d{4}',row['code'])
    assert row['category'] in ('A','B,quoted','C\nline')
    assert row['status'] in ('active','archived')
    assert row['note']=='a,"b"\r\nc' and row['optional'] in (None,'optional')
    assert row['address'].startswith('测试省') and row['company'].startswith('示例')
    assert row['sentence'].endswith('。') and row['sentence'].count('，')==2
report={'date':datetime.datetime.now(datetime.timezone.utc).isoformat(),'python':platform.python_version(),
        'rows':len(rows),'columns':len(schema['columns']),'passed':True,
        'validators':['uuid','ipaddress','datetime','decimal','csv','json','urllib.parse','re','GS1 modulo-10 invariant'],
        'sha256':{name:hashlib.sha256((folder/name).read_bytes()).hexdigest() for name in ('records.json','records.jsonl','records.csv','records-schema.json')},
        'scope':'Format and deterministic dataset validation; no Python Faker sequence, locale-corpus, distribution or identifier-allocation parity claim.'}
(folder/'python-validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'rows':len(rows),'columns':len(schema['columns']),'passed':True}))
