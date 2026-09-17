import sys,json
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from faker import Faker,VERSION
root=Path(__file__).resolve().parents[1];data=json.loads((root/'evidence/statistical-counts.json').read_text(encoding='utf8'));n=data['n']
def chi(observed,probabilities):return sum((o-n*p)**2/(n*p)for o,p in zip(observed,probabilities))
uniform=chi(data['uniform'],[1/20]*20);weighted=chi(data['weighted'],[.1,.3,.6])
provider=next(p for p in Faker('zh_CN').providers if p.__module__=='faker.providers.person.zh_CN');weights=provider.last_names;total=sum(weights.values());observed=[0]*10;expected=[0.0]*10;cumulative=0
assert set(data['surnames'])<=set(weights)
for name,weight in weights.items():
    bucket=min(9,int(cumulative/total*10));observed[bucket]+=data['surnames'].get(name,0);expected[bucket]+=weight/total;cumulative+=weight
surname=chi(observed,expected);mean=data['sum']/n;variance=data['squares']/n-mean*mean
correlation=(data['products']/(n-1)-((data['sum']-data['last'])/(n-1))*((data['sum']-data['first'])/(n-1)))/variance
assert uniform<43.83,(uniform,'uniform');assert weighted<13.82,(weighted,'weighted');assert surname<27.88,(surname,'surnames');assert abs(correlation)<.02,correlation
report={'n':n,'reference':'Faker '+VERSION+' zh_CN surname weights read independently','uniformChiSquare':uniform,'weightedChiSquare':weighted,'surnameChiSquare':surname,'lagOneCorrelation':correlation,'thresholds':{'uniform':43.83,'weighted':13.82,'surname':27.88,'absoluteCorrelation':.02},'passed':True,'scope':'One preregistered seed, 100000 rows; broad sanity thresholds, not an RNG quality certification'}
(root/'evidence/statistical-validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8',newline='\n');print(json.dumps(report))
