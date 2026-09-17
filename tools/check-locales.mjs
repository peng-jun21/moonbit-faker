// Offline replay of independently captured reference outputs against the shipped engine.
import fs from 'node:fs/promises';import assert from 'node:assert/strict';import {run,session} from '../web/engine.mjs';
const report=JSON.parse(await fs.readFile(new URL('../evidence/locale-comparison.json',import.meta.url),'utf8'));
const catalog=JSON.parse(session('{"op":"catalog"}')).locales,seen=new Set();let values=0;
for(const row of report.rows){assert.equal(row.reference.version,'40.39.0');assert(Array.isArray(row.reference.values));const actual=JSON.parse(run(JSON.stringify({seed:row.seed,count:row.count,columns:[{name:'value',provider:'localized',locale:row.locale,method:row.method}]}))).map(r=>r.value);assert.deepEqual(actual,row.reference.values,`${row.locale}/${row.method}/${row.seed}`);seen.add(row.locale+'/'+row.method);values+=actual.length;}
assert.equal(seen.size,Object.values(catalog).reduce((n,methods)=>n+methods.length,0));
console.log(JSON.stringify({referenceCases:report.rows.length,localeMethods:seen.size,values,passed:true}));
