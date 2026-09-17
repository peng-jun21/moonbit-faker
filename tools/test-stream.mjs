import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';import {DataSession,generateJob,validateJob} from './session-runtime.mjs';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url))),temporary=await fs.mkdtemp(path.join(os.tmpdir(),'faker-stream-')),groups=[];
const job={seed:123,count:400,columns:[{name:'id',provider:'sequence',start:1,unique:true},{name:'code',provider:'uuid4',unique:true},{name:'name',provider:'localized',locale:'fr_FR',method:'name'},{name:'quoted',provider:'constant',value:'"quoted",\nline'}]};
const collect=async(job,options)=>{const rows=[];const state=await generateJob(job,async line=>rows.push(line),options);return {text:rows.join(''),...state};};
const cli=(args,input)=>spawnSync(process.execPath,[path.join(root,'tools/stream.mjs'),...args],{input,encoding:'utf8',timeout:30000,maxBuffer:16000000});
async function group(name,fn){await fn();groups.push(name);}
let performanceRecord;
try{
 await group('Batch boundaries and checkpoint preserve exact complete sequence',async()=>{
  const baseline=await collect(job,{batchSize:1}),chunked=await collect(job,{batchSize:127});assert.equal(chunked.text,baseline.text);
  const first=await collect(job,{limit:137}),rest=await collect(job,{checkpoint:first.checkpoint});assert.equal(first.text+rest.text,baseline.text);assert.equal(rest.checkpoint.index,400);
  const rows=baseline.text.trim().split('\n').map(JSON.parse);assert.equal(new Set(rows.map(r=>r.code)).size,400);assert.deepEqual(rows.map(r=>r.id),Array.from({length:400},(_,i)=>i+1));
 });
 await group('Related datasets preserve whole-record foreign relationships',async()=>{
  const related={datasets:[{name:'customers',count:100,seed:7,schema:{type:'object',fields:[{name:'id',provider:'sequence'},{name:'name',provider:'localized',locale:'zh_CN',method:'name'}]}},{name:'orders',count:1000,seed:8,schema:{type:'object',fields:[{name:'id',provider:'sequence'},{name:'customer',type:'foreign',table:'customers',path:''},{name:'customer_id',type:'ref',path:'/customer/id'},{name:'customer_name',type:'ref',path:'/customer/name'},{name:'tags',type:'array',min:1,max:4,items:{provider:'choice',values:['new','paid','sample']}}]}}]};
  const result=await collect(related);const rows=result.text.trim().split('\n').map(JSON.parse),customers=new Map(rows.filter(r=>r.dataset==='customers').map(r=>[r.row.id,r.row]));
  assert.equal(rows.length,1100);for(const {row}of rows.filter(r=>r.dataset==='orders')){assert.deepEqual(row.customer,customers.get(row.customer_id));assert.equal(row.customer_name,row.customer.name);assert(row.tags.length>=1&&row.tags.length<=4);}
  assert.throws(()=>validateJob({datasets:[related.datasets[1]]}),/earlier/);
  assert.throws(()=>validateJob({datasets:[{...related.datasets[0],count:50001},related.datasets[1]]}),/50000/);
  const special=structuredClone(related);special.datasets[0].name='__proto__';special.datasets[0].count=2;special.datasets[1].count=3;special.datasets[1].schema.fields[1].table='__proto__';
  const prototypeRows=(await collect(special)).text.trim().split('\n').map(JSON.parse);assert.equal(prototypeRows.length,5);assert.equal(prototypeRows[2].row.customer_name,prototypeRows[2].row.customer.name);
 });
 await group('Awaited consumer backpressure and write failure cleanup',async()=>{
  let active=0,maxActive=0,count=0;
  await generateJob({...job,count:25},async()=>{active++;maxActive=Math.max(maxActive,active);await new Promise(resolve=>setTimeout(resolve,2));active--;count++;});assert.equal(count,25);assert.equal(maxActive,1);
  await assert.rejects(generateJob(job,async()=>{throw Error('sink failed');}),/sink failed/);
 });
 await group('Cancellation stops current delivery and operation timeout recovers',async()=>{
  const controller=new AbortController();let written=0;
  await assert.rejects(generateJob({...job,count:10000},async()=>{if(++written===20)controller.abort(Error('cancelled'));},{signal:controller.signal}),/cancelled/);assert.equal(written,20);
  await assert.rejects(DataSession.open({columns:job.columns},{timeoutMs:1}),/timeout/);
  assert.equal((await collect({...job,count:2})).emitted,2);
 });
 await group('Row failure emits only committed rows and handles bounded uniqueness',async()=>{
  let written=0;await assert.rejects(generateJob({count:2,columns:[{name:'x',provider:'constant',value:'only',unique:true}]},async()=>written++),/unique retry/);assert.equal(written,1);
  const instance=await DataSession.open({schema:{provider:'integer',min:1,max:1}});try{const pending=instance.nextBatch(256);await assert.rejects(instance.nextBatch(),/Concurrent/);assert.equal((await pending).rows.length,256);}finally{await instance.close();}
 });
 await group('Independent Python CSV Unicode multiline and nested cell parsing',async()=>{
  const csv=await collect({...job,format:'csv'});const file=path.join(temporary,'records.csv');await fs.writeFile(file,csv.text);
  const python=spawnSync('python',['-c',"import csv,sys; r=list(csv.DictReader(open(sys.argv[1],encoding='utf8',newline=''))); assert len(r)==400; assert r[0]['id']=='1'; assert r[-1]['id']=='400'; assert r[0]['quoted']=='\"quoted\",\\nline'; print('ok')",file],{encoding:'utf8'});assert.equal(python.status,0,python.stderr);
  const nested=await collect({count:2,format:'csv',schema:{type:'object',fields:[{name:'items',type:'array',min:2,max:2,items:{provider:'constant',value:1}}]}});assert.match(nested.text,/\[1,1\]/);
 });
 await group('Actual CLI pause/resume segments match one uninterrupted output',async()=>{
  const jobPath=path.join(temporary,'job.json'),one=path.join(temporary,'one.jsonl'),two=path.join(temporary,'two.jsonl'),state=path.join(temporary,'state.json');await fs.writeFile(jobPath,JSON.stringify(job));
  const a=cli(['--job',jobPath,'--out',one,'--limit','67','--checkpoint',state]);assert.equal(a.status,0,a.stderr);assert.equal(JSON.parse(a.stdout).emitted,67);
  const b=cli(['--resume',state,'--out',two]);assert.equal(b.status,0,b.stderr);assert.equal(JSON.parse(b.stdout).emitted,333);
  const baseline=await collect(job);assert.equal((await fs.readFile(one,'utf8'))+(await fs.readFile(two,'utf8')),baseline.text);
  const bad=JSON.parse(await fs.readFile(state,'utf8'));bad.checkpoint.index++;const corrupt=path.join(temporary,'corrupt.json');await fs.writeFile(corrupt,JSON.stringify(bad));assert.notEqual(cli(['--resume',corrupt]).status,0);
  await fs.appendFile(one,'corrupted');assert.match(cli(['--resume',state]).stderr,/no longer matches/);
 });
 await group('Actual CLI no overwrite strict UTF-8 byte budgets and temporary cleanup',async()=>{
  const keep=path.join(temporary,'keep.jsonl');await fs.writeFile(keep,'original');const request=JSON.stringify({...job,count:3});
  const refused=cli(['--out',keep],request);assert.notEqual(refused.status,0);assert.equal(await fs.readFile(keep,'utf8'),'original');
  const replaced=cli(['--out',keep,'--force'],request);assert.equal(replaced.status,0,replaced.stderr);assert.equal((await fs.readFile(keep,'utf8')).trim().split('\n').length,3);
  const target=path.join(temporary,'limited.jsonl');assert.notEqual(cli(['--out',target,'--max-bytes','1'],request).status,0);await assert.rejects(fs.stat(target),{code:'ENOENT'});
  const invalid=path.join(temporary,'invalid.json');await fs.writeFile(invalid,Buffer.from([0xff]));assert.notEqual(cli(['--job',invalid]).status,0);
  const fail=JSON.stringify({count:2,columns:[{name:'x',provider:'constant',value:'only',unique:true}]});assert.notEqual(cli(['--out',target],fail).status,0);await assert.rejects(fs.stat(target),{code:'ENOENT'});
  assert(!(await fs.readdir(temporary)).some(name=>name.startsWith('.faker-')));
 });
 await group('100000-row stream keeps sequence unique across batches without buffering output',async()=>{
  const large={seed:42,count:100000,columns:[{name:'id',provider:'sequence',unique:true},{name:'name',provider:'localized',locale:'en_US',method:'name'},{name:'value',provider:'integer',min:0,max:99999}]};
  let index=0,bytes=0,peakRss=process.memoryUsage().rss;const hash=createHash('sha256'),start=performance.now();
  const result=await generateJob(large,async line=>{const row=JSON.parse(line);assert.equal(row.id,index++);bytes+=Buffer.byteLength(line);hash.update(line);if(index%1000===0)peakRss=Math.max(peakRss,process.memoryUsage().rss);});
  assert.equal(result.emitted,100000);assert.equal(result.checkpoint.index,100000);assert.equal(result.checkpoint.seen['/0'].length,100000);
  performanceRecord={rows:index,bytes,sha256:hash.digest('hex'),elapsedMs:performance.now()-start,sampledProcessPeakRssBytes:peakRss,runtime:process.version,cpu:os.cpus()[0].model,scope:'Worker, JSON, validation and checkpoint; host RSS samples include worker heap; no exact peak or upstream throughput claim'};
 });
 await fs.writeFile(path.join(root,'evidence/stream-validation.json'),JSON.stringify({date:new Date().toISOString(),runtime:process.version,groups,passed:groups.length,largeStream:performanceRecord},null,2)+'\n');console.log(JSON.stringify({passed:groups.length,largeStream:performanceRecord}));
}finally{const real=await fs.realpath(temporary),tmp=await fs.realpath(os.tmpdir());if(path.dirname(real).toLowerCase()!==tmp.toLowerCase()||!path.basename(real).startsWith('faker-stream-'))throw Error('Unsafe test cleanup');await fs.rm(real,{recursive:true,force:true});}
