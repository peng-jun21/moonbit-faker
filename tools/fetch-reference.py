"""Fetch the pinned official wheel into a separate reference directory, never production."""
import hashlib,json,sys,urllib.request,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
provenance=json.loads((root/'data/provenance.json').read_text(encoding='utf8'))['wheel']
target=Path(sys.argv[1]).resolve()
if target==root or root in target.parents:raise SystemExit('Reference directory must be outside this repository')
target.mkdir(parents=True,exist_ok=True);wheel=target/provenance['filename']
if not wheel.exists():
    with urllib.request.urlopen(provenance['url'],timeout=60)as response:content=response.read()
    if hashlib.sha256(content).hexdigest()!=provenance['sha256']:raise SystemExit('Wheel digest mismatch')
    wheel.write_bytes(content)
if hashlib.sha256(wheel.read_bytes()).hexdigest()!=provenance['sha256']:raise SystemExit('Wheel digest mismatch')
site=target/'site';site.mkdir(exist_ok=True)
with zipfile.ZipFile(wheel)as archive:
    for member in archive.infolist():
        dest=(site/member.filename).resolve()
        if site not in dest.parents:raise SystemExit('Unsafe wheel member')
    archive.extractall(site)
(target/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf8',newline='\n')
print(site)
