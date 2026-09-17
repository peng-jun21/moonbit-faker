import {Worker} from 'node:worker_threads';

export class DataSession {
 #worker;#pending;#counter=0;#closed=false;#closePromise;#signal;#abort;#timeout;
 constructor({signal,timeoutMs=30000}={}){
  if(!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>300000)throw Error('timeoutMs must be 1..300000');
  if(signal?.aborted)throw signal.reason??Error('Aborted');
  this.#timeout=timeoutMs;this.#signal=signal;
  this.#worker=new Worker(new URL('./session-worker.mjs',import.meta.url),{execArgv:process.execArgv.filter(a=>!a.startsWith('--input-type')),resourceLimits:{maxOldGenerationSizeMb:512}});
  this.#worker.on('message',message=>{const pending=this.#pending;if(!pending||pending.id!==message.id)return;this.#pending=undefined;clearTimeout(pending.timer);message.error?pending.reject(Error(message.error)):pending.resolve(message.result);});
  this.#worker.on('error',error=>this.close(error));
  this.#worker.on('exit',code=>{if(!this.#closed)this.close(Error('Worker exited: '+code));});
  this.#abort=()=>this.close(signal.reason??Error('Aborted'));signal?.addEventListener('abort',this.#abort,{once:true});
 }
 async #call(message){
  if(this.#closed)throw Error('Session is closed');if(this.#pending)throw Error('Concurrent session operation is not allowed');
  return new Promise((resolve,reject)=>{const id=++this.#counter,timer=setTimeout(()=>this.close(Error('Generation timeout')),this.#timeout);this.#pending={id,resolve,reject,timer};try{this.#worker.postMessage({...message,id});}catch(error){this.close(error);}});
 }
 static async open(definition,options){const instance=new DataSession(options);try{const {index}=await instance.#call({op:'open',definition});instance.index=index;return instance;}catch(error){await instance.close();throw error;}}
 async nextBatch(count=128){const result=await this.#call({op:'next',count});if(result.index!==undefined)this.index=result.index;return result;}
 checkpoint(){return this.#call({op:'checkpoint'});}
 close(reason=Error('Session closed')){
  if(this.#closePromise)return this.#closePromise;this.#closed=true;this.#signal?.removeEventListener('abort',this.#abort);
  if(this.#pending){clearTimeout(this.#pending.timer);this.#pending.reject(reason);this.#pending=undefined;}
  this.#closePromise=this.#worker.terminate().then(()=>{});return this.#closePromise;
 }
}

function keys(value,allowed){if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Job object required');for(const key of Object.keys(value))if(!allowed.includes(key))throw Error('Unknown job option: '+key);}
function count(value){if(!Number.isInteger(value)||value<0||value>10000000)throw Error('count must be 0..10000000');return value;}
const definition=job=>{const result={seed:job.seed??0};for(const name of ['schema','columns','tables'])if(Object.hasOwn(job,name))result[name]=job[name];return result;};
function foreignTables(schema,result=new Set()){if(!schema||typeof schema!=='object')return result;if(schema.type==='foreign')result.add(schema.table);for(const value of Object.values(schema))if(Array.isArray(value))for(const child of value)foreignTables(child,result);else if(value&&typeof value==='object')foreignTables(value,result);return result;}
export function validateJob(job){
 keys(job,['seed','count','schema','columns','tables','format','datasets']);const format=job.format??'jsonl';if(!['jsonl','csv'].includes(format))throw Error('Stream format must be jsonl or csv');
 if(job.datasets!==undefined){
  if(format!=='jsonl'||!Array.isArray(job.datasets)||job.datasets.length<1||job.datasets.length>16)throw Error('datasets requires 1..16 definitions and JSONL output');
  if(['schema','columns','count','tables','seed'].some(k=>Object.hasOwn(job,k)))throw Error('datasets cannot mix with single-dataset options');
  const names=new Set(),required=new Set();
  for(const dataset of job.datasets){keys(dataset,['name','seed','count','schema','columns']);if(typeof dataset.name!=='string'||!dataset.name.length||dataset.name.length>80||names.has(dataset.name))throw Error('Invalid dataset name');count(dataset.count);for(const table of foreignTables(dataset.schema)){if(!names.has(table))throw Error('Foreign dataset must be defined earlier: '+table);required.add(table);}names.add(dataset.name);}
  for(const dataset of job.datasets)if(required.has(dataset.name)&&dataset.count>50000)throw Error('Referenced dataset exceeds 50000 rows');
  return {format,datasets:job.datasets,required,multiple:true};
 }
 count(job.count??10);if(Object.hasOwn(job,'schema')===Object.hasOwn(job,'columns'))throw Error('Supply schema or columns');
 return {format,datasets:[{...job,count:job.count??10,name:'records'}],required:new Set(),multiple:false};
}
const quote=value=>'"'+String(value).replaceAll('"','""')+'"';
export function csvRow(row,headers){if(!row||typeof row!=='object'||Array.isArray(row)||Object.keys(row).length!==headers.length||headers.some(k=>!Object.hasOwn(row,k)))throw Error('CSV requires consistent object fields');return headers.map(k=>quote(row[k]===null?'':typeof row[k]==='string'?row[k]:JSON.stringify(row[k]))).join(',')+'\r\n';}
export function csvHeaders(job){const fields=job.columns??(job.schema?.type==='object'?job.schema.fields:undefined);if(!Array.isArray(fields))throw Error('CSV requires an object schema');return fields.map(f=>f.name);}

// Backpressure is represented by the awaited write function. Only one batch is in flight.
export async function generateJob(job,write,{signal,timeoutMs=30000,batchSize=128,limit,checkpoint,onProgress}={}){
 const plan=validateJob(job);if(!Number.isInteger(batchSize)||batchSize<1||batchSize>256)throw Error('batchSize must be 1..256');
 if(limit!==undefined)count(limit);if(plan.multiple&&(limit!==undefined||checkpoint))throw Error('Pause/resume currently requires a single dataset');
 let emitted=0,retainedText=0,finalState;const tables=Object.create(null);
 for(const dataset of plan.datasets){
  const def=definition(dataset);if(plan.multiple)def.tables=tables;if(checkpoint)def.checkpoint=checkpoint;
  const instance=await DataSession.open(def,{signal,timeoutMs});const retained=[];
  try{
   if(instance.index>dataset.count)throw Error('Checkpoint is beyond requested count');
   const end=Math.min(dataset.count,instance.index+(limit??dataset.count));
   const headers=plan.format==='csv'?csvHeaders(dataset):undefined;
   if(headers)await write(headers.map(quote).join(',')+'\r\n');
   while(instance.index<end){
    const result=await instance.nextBatch(Math.min(batchSize,end-instance.index));
    for(const row of result.rows){
     if(signal?.aborted)throw signal.reason??Error('Aborted');
     if(plan.required.has(dataset.name)){retainedText+=JSON.stringify(row).length;if(retainedText>8000000)throw Error('Retained foreign dataset text budget');retained.push(row);}
     await write(headers?csvRow(row,headers):JSON.stringify(plan.multiple?{dataset:dataset.name,row}:row)+'\n');emitted++;
    }
    onProgress?.({dataset:dataset.name,index:instance.index,emitted});
    if(result.error)throw Error(result.error);
   }
   if(!plan.multiple)finalState=await instance.checkpoint();
  }finally{await instance.close();}
  if(plan.required.has(dataset.name)){if(!retained.length)throw Error('Referenced dataset is empty: '+dataset.name);tables[dataset.name]=retained;}
 }
 return {emitted,checkpoint:finalState};
}
