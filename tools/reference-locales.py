"""Run unmodified Faker providers with an explicitly substituted deterministic RNG."""
import sys,json,random
sys.stdout.reconfigure(encoding='utf8')
sys.path.insert(0,sys.argv[1])
from faker import Faker,VERSION
assert VERSION == "40.39.0", "Reference version mismatch"
class XorShift(random.Random):
    def __init__(self,seed):super().__init__(0);self.state=seed or 0x9e3779b9
    def next32(self):
        x=self.state;x^=(x<<13)&0xffffffff;x^=x>>17;x^=(x<<5)&0xffffffff;self.state=x&0xffffffff;return self.state
    def random(self):return self.next32()/4294967296
    def randrange(self,start,stop=None,step=1):
        if stop is None:start,stop=0,start
        count=len(range(start,stop,step));assert count>0
        threshold=(2**32-count)%count;x=self.next32()
        while x<threshold:x=self.next32()
        return start+(x%count)*step
    def choice(self,seq):return seq[self.randrange(len(seq))]
    def randint(self,a,b):return self.randrange(a,b+1)
    def getrandbits(self,k):
        raise RuntimeError('Unsupported reference random operation getrandbits')
if __name__=='__main__':
    fakes={}
    for line in sys.stdin:
        job=json.loads(line)
        try:
            if job['locale'] not in fakes:fakes[job['locale']]=Faker(job['locale'])
            fake=fakes[job['locale']]
            fake.random=XorShift(job['seed'])
            values=[getattr(fake,job['method'])()for _ in range(job['count'])]
            result={'values':values,'version':VERSION}
        except Exception as e:result={'error':repr(e),'version':VERSION}
        print(json.dumps(result,ensure_ascii=False))
