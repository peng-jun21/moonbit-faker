"""Same table construction and JSON serialization; provider code unchanged, RNG adapted."""
import sys,json,hashlib,time,statistics,platform
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from importlib.util import spec_from_file_location,module_from_spec
spec=spec_from_file_location('reference_locales',Path(__file__).with_name('reference-locales.py'));module=module_from_spec(spec);spec.loader.exec_module(module)
jobs=json.loads(sys.stdin.read());result=[]
for job in jobs:
    fake=module.Faker(job['locale']);provider=getattr(fake,job['method']);samples=[];digests=[]
    for iteration in range(8):
        fake.random=module.XorShift(42);start=time.perf_counter_ns()
        body=json.dumps([{'value':provider()}for _ in range(job['count'])],ensure_ascii=False,separators=(',',':'))
        elapsed=(time.perf_counter_ns()-start)/1e6
        if iteration:samples.append(elapsed);digests.append(hashlib.sha256(body.encode()).hexdigest())
    assert len(set(digests))==1
    result.append({**job,'samplesMs':samples,'medianMs':statistics.median(samples),'sha256':digests[0],'bytes':len(body.encode())})
print(json.dumps({'python':platform.python_version(),'reference':'Faker '+module.VERSION,'cases':result}))
