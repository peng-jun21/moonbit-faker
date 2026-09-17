import fs from 'node:fs/promises';import {generateJob} from './session-runtime.mjs';
const n=100000,uniform=Array(20).fill(0),weighted=Array(3).fill(0),surnames={};let sum=0,squares=0,products=0,previous,first,last;
const job={seed:198703,count:n,columns:[{name:'u',provider:'integer',min:0,max:19},{name:'w',provider:'weighted_choice',values:['a','b','c'],weights:[1,3,6]},{name:'name',provider:'localized',locale:'zh_CN',method:'last_name'}]};
await generateJob(job,async line=>{const r=JSON.parse(line);uniform[r.u]++;weighted['abc'.indexOf(r.w)]++;surnames[r.name]=(surnames[r.name]??0)+1;sum+=r.u;squares+=r.u*r.u;if(previous!==undefined)products+=previous*r.u;else first=r.u;previous=r.u;last=r.u;});
const report={n,seed:job.seed,uniform,weighted,surnames,sum,squares,products,first,last,scope:'Fixed-seed distribution sanity check; no statistical or cryptographic guarantee'};
await fs.writeFile(new URL('../evidence/statistical-counts.json',import.meta.url),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({n,uniform,weighted,distinctSurnames:Object.keys(surnames).length}));
