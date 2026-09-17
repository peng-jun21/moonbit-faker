"""Export attributed Faker data, not Python implementation code. Pass reference/site."""
import sys,json,hashlib,inspect,shutil,re
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1]).resolve()))
from faker import Faker,VERSION
assert VERSION == "40.39.0", "Reference version mismatch"
root=Path(__file__).resolve().parents[1]
locales=['en_US','zh_CN','en_GB','de_DE','fr_FR','ja_JP'];catalog={};sources={}
def table(data,mode='literal'):
    if isinstance(data,str):data=[data]
    weighted=isinstance(data,dict) and all(isinstance(v,(int,float))for v in data.values())
    values=list(data);assert values and all(isinstance(v,str)for v in values)
    return {'values':values,'weights':list(data.values())if weighted else [1.0]*len(values),'weighted':weighted,'mode':mode}
for locale in locales:
    fake=Faker(locale);providers={p.__module__.split('.')[2]:p for p in fake.providers};out={}
    def add(method,module,attribute,mode='literal',fallback=None):
        p=providers[module];data=getattr(p,attribute,fallback)
        if data is None:return
        out[method]=table(data,mode)
        for cls in type(p).__mro__:
            if cls is object:continue
            source=inspect.getsourcefile(cls)
            if source and '/faker/'in Path(source).as_posix():
                file=Path(source);sources[file.as_posix().split('/faker/',1)[1]]=hashlib.sha256(file.read_bytes()).hexdigest()
    for gender in ['', '_male','_female']:
        add('name'+gender,'person','formats'+gender,'template',getattr(providers['person'],'formats'))
        add('first_name'+gender,'person','first_names'+gender,fallback=getattr(providers['person'],'first_names'))
        add('last_name'+gender,'person','last_names'+gender,fallback=getattr(providers['person'],'last_names'))
        for kind in ['prefix','suffix']:
            base=getattr(providers['person'],kind+'es',None)
            if base is None:base=['']
            add(kind+gender,'person',kind+'es'+gender,fallback=base)
    for kind in ['prefix','suffix']:
        p=providers['person'];attr=kind+'es'
        if not hasattr(p,attr) and hasattr(p,attr+'_male') and hasattr(p,attr+'_female'):
            if hasattr(p,attr+'_nonbinary'):
                from faker.utils.datasets import add_ordereddicts
                out[kind]=table(add_ordereddicts(getattr(p,attr+'_male'),getattr(p,attr+'_female'),getattr(p,attr+'_nonbinary')))
            else:out[kind]=table([kind+'_male',kind+'_female'],'delegate')
    direct={'job':('job','jobs'),'word':('lorem','word_list'),'country':('address','countries'),'country_code':('address','alpha_2_country_codes'),'state':('address','states'),'state_abbr':('address','states_abbr'),'province':('address','provinces'),'prefecture':('address','prefectures'),'county':('address','counties'),'city_name':('address','cities'),'district':('address','districts'),'town':('address','towns'),'building_name':('address','building_names'),'city_prefix':('address','city_prefixes'),'city_suffix':('address','city_suffixes'),'street_suffix':('address','street_suffixes'),'street_prefix':('address','street_prefixes'),'street_suffix_long':('address','street_suffixes_long'),'street_suffix_short':('address','street_suffixes_short'),'company_prefix':('company','company_prefixes'),'company_suffix':('company','company_suffixes'),'company_category':('company','company_categories'),'military_ship':('address','military_ship_prefix'),'military_state':('address','military_state_abbr'),'color_name':('color','all_colors')}
    for method,(module,attr)in direct.items():add(method,module,attr)
    templates={'address':('address','address_formats'),'city':('address','city_formats'),'street_address':('address','street_address_formats'),'street_name':('address','street_name_formats'),'postcode':('address','postcode_formats'),'building_number':('address','building_number_formats'),'secondary_address':('address','secondary_address_formats'),'military_apo':('address','military_apo_format'),'military_dpo':('address','military_dpo_format'),'company':('company','formats'),'phone_number':('phone_number','formats')}
    for method,(module,attr)in templates.items():add(method,module,attr,'template')
    if locale=='en_US':
        p=providers['address'];out['state_abbr']=table(p.states_abbr+p.territories_abbr+p.freely_associated_states_abbr)
        out['postcode']=table([''],'us_postcode')
        for method in ['military_apo','military_dpo']:out[method]['mode']='fixed_template'
    if locale=='en_GB':
        out['postcode']['mode']='gb_postcode'
        for key,values in providers['address']._postcode_sets.items():out['postcode_set_'+key]=table(values if not isinstance(values,str)else list(values))
    if locale=='fr_FR':
        out['postcode']=table([number for number,name in providers['address'].departments],'fr_postcode')
        add('area_code_without_separator','phone_number','area_codes','template')
        out['area_code_with_separator']=table([v[0]+' '+v[1:] for v in providers['phone_number'].area_codes],'template')
    if locale=='ja_JP':
        out.pop('city_name')
        for method in ['last_name','last_name_male','last_name_female']:
            out[method]=table({pair[0]:weight for pair,weight in providers['person'].last_name_pairs.items()})
        add('city','address','cities');out['postcode']=table([''],'jp_postcode')
        for name,maximum,suffix in [('chome',42,'丁目'),('ban',27,'番'),('gou',20,'号')]:out[name]=table([str(i)+suffix for i in range(1,maximum+1)])
    # All format references resolve, including country-specific method expansions.
    for method,t in out.items():
        if t['mode']=='template':
            for value in t['values']:
                for dependency in re.findall(r'{{(.*?)}}',value):assert dependency in out,(locale,method,dependency)
    catalog[locale]=out
(root/'data').mkdir(exist_ok=True);(root/'third_party').mkdir(exist_ok=True)
data=json.dumps(catalog,ensure_ascii=False,separators=(',',':'))
(root/'data/locales.json').write_text(data+'\n',encoding='utf8',newline='\n')
(root/'locale_data.mbt').write_text('// Generated by tools/export-locales.py. Data from Faker '+VERSION+'; see third_party/Faker-LICENSE.txt.\n///|\nlet locale_source : String = [\n'+',\n'.join('  '+json.dumps(data[i:i+4000],ensure_ascii=False) for i in range(0,len(data),4000))+'\n].join("")\n',encoding='utf8',newline='\n')
license_file=next(Path(sys.argv[1]).glob('faker-*.dist-info/licenses/LICENSE.txt'));shutil.copyfile(license_file,root/'third_party/Faker-LICENSE.txt')
provenance=json.loads((Path(sys.argv[1]).parent/'provenance.json').read_text(encoding='utf8'))
report={'version':VERSION,'wheel':provenance,'sourceSHA256':sources,'dataSHA256':hashlib.sha256((data+'\n').encode()).hexdigest(),'locales':{k:{'methods':len(v),'entries':sum(len(t['values'])for t in v.values())}for k,v in catalog.items()},'scope':'Explicit provider data and template conventions. Fallback modules match Faker provider resolution. No complete locale/API claim.'}
(root/'data/provenance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
print(json.dumps(report['locales']))
