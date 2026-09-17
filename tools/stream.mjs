import fs from 'node:fs/promises';import {createReadStream} from 'node:fs';import path from 'node:path';import {createHash,randomUUID} from 'node:crypto';import {generateJob,validateJob} from './session-runtime.mjs';
const args=process.argv.slice(2);let out,jobFile,resumeFile,checkpointFile,force=false,limit,timeoutMs=30000,maxBytes=268435456;
let temporary,handle;const controller=new AbortController();const interrupted=()=>controller.abort(Error('Generation interrupted'));process.once('SIGINT',interrupted);process.once('SIGTERM',interrupted);
const canonicalDigest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
async function readJSON(file,max){const stat=await fs.stat(file);if(stat.size>max)throw Error('JSON file size limit');return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(await fs.readFile(file)));}
async function exists(file){try{await fs.lstat(file);return true;}catch(error){if(error.code==='ENOENT')return false;throw error;}}
async function publish(temp,target){if(force)await fs.rename(temp,target);else{await fs.link(temp,target);await fs.unlink(temp);}}
async function writeCheckpoint(file,data){const target=path.resolve(file);await fs.mkdir(path.dirname(target),{recursive:true});const temp=path.join(path.dirname(target),'.faker-'+randomUUID()+'.tmp');const bytes=Buffer.from(JSON.stringify(data)+'\n');if(bytes.length>67108864)throw Error('Checkpoint exceeds 64 MiB');const h=await fs.open(temp,'wx');try{try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}await publish(temp,target);}catch(error){await fs.unlink(temp).catch(()=>{});throw error;}}
try{
 for(let i=0;i<args.length;i++){
  const a=args[i];if(a==='--help'){console.log('Usage: node tools/stream.mjs --job FILE [--out FILE] [--force] [--limit N] [--checkpoint STATE]\nResume: --resume STATE --out NEW_FILE [--checkpoint NEXT_STATE]\nNo --job/--resume: UTF-8 JSON stdin. JSONL or CSV, single or related datasets.\n--timeout MS (default 30000 per worker operation), --max-bytes N (default 256 MiB).\nOutput files are atomic and never appended. Checkpoints require --out; pause/resume is single-dataset only.');process.exit(0);}
  if(a==='--force'){force=true;continue;}
  if(!['--job','--out','--resume','--checkpoint','--limit','--timeout','--max-bytes'].includes(a)||++i>=args.length)throw Error('Unknown or missing option '+a);
  if(a==='--job')jobFile=args[i];else if(a==='--out')out=args[i];else if(a==='--resume')resumeFile=args[i];else if(a==='--checkpoint')checkpointFile=args[i];else if(a==='--limit')limit=Number(args[i]);else if(a==='--timeout')timeoutMs=Number(args[i]);else maxBytes=Number(args[i]);
 }
 if(jobFile&&resumeFile)throw Error('Use --job or --resume');if(checkpointFile&&!out)throw Error('Checkpoint requires file output');
 if(!Number.isInteger(maxBytes)||maxBytes<1||maxBytes>2147483647)throw Error('max-bytes must be 1..2147483647');
 for(const target of [out,checkpointFile].filter(Boolean)){if(!force&&await exists(target))throw Error('Refusing existing file: '+target);if(jobFile&&path.resolve(target)===path.resolve(jobFile))throw Error('Output cannot replace the job file');}
 if(out&&checkpointFile&&path.resolve(out)===path.resolve(checkpointFile))throw Error('Data and checkpoint paths must differ');
 let job,checkpoint;
 if(resumeFile){
  const saved=await readJSON(resumeFile,67108864);const payload={job:saved.job,checkpoint:saved.checkpoint,output:saved.output};
  if(saved.version!==1||saved.sha256!==canonicalDigest(payload))throw Error('Checkpoint integrity mismatch');job=saved.job;checkpoint=saved.checkpoint;
  const previous=path.resolve(path.dirname(path.resolve(resumeFile)),saved.output.file);if(out&&path.resolve(out)===previous)throw Error('Resume must write a new output segment');
  const hash=createHash('sha256');let length=0;for await(const chunk of createReadStream(previous)){hash.update(chunk);length+=chunk.length;}
  if(hash.digest('hex')!==saved.output.sha256||length!==saved.output.bytes)throw Error('Previous output segment no longer matches checkpoint');
 }else if(jobFile)job=await readJSON(jobFile,16777216);else{const chunks=[];let size=0;for await(const chunk of process.stdin){size+=chunk.length;if(size>16777216)throw Error('Job exceeds 16 MiB');chunks.push(chunk);}job=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));}
 const plan=validateJob(job);if(plan.multiple&&(checkpointFile||resumeFile))throw Error('Pause/resume requires a single dataset');
 if(out){out=path.resolve(out);await fs.mkdir(path.dirname(out),{recursive:true});temporary=path.join(path.dirname(out),'.faker-'+randomUUID()+'.tmp');handle=await fs.open(temporary,'wx');}
 let bytes=0;const hash=createHash('sha256');
 const write=async text=>{if(controller.signal.aborted)throw controller.signal.reason;const chunk=Buffer.from(text);bytes+=chunk.length;if(bytes>maxBytes)throw Error('Output byte budget exceeded');hash.update(chunk);if(handle)await handle.writeFile(chunk);else await new Promise((resolve,reject)=>process.stdout.write(chunk,error=>error?reject(error):resolve()));};
 const result=await generateJob(job,write,{signal:controller.signal,timeoutMs,limit,checkpoint});
 if(handle){await handle.sync();await handle.close();handle=undefined;await publish(temporary,out);temporary=undefined;}
 const output={file:checkpointFile?path.relative(path.dirname(path.resolve(checkpointFile)),out):out,bytes,sha256:hash.digest('hex')};
 if(checkpointFile){const payload={job,checkpoint:result.checkpoint,output};await writeCheckpoint(checkpointFile,{version:1,...payload,sha256:canonicalDigest(payload)});}
 if(out)console.log(JSON.stringify({ok:true,emitted:result.emitted,index:result.checkpoint?.index,output:out,bytes,checkpoint:checkpointFile?path.resolve(checkpointFile):undefined}));
}catch(error){if(handle)await handle.close().catch(()=>{});if(temporary)await fs.unlink(temporary).catch(()=>{});process.stderr.write(JSON.stringify({ok:false,error:String(error.message||error)})+'\n');process.exitCode=controller.signal.aborted?130:1;}
finally{process.removeListener('SIGINT',interrupted);process.removeListener('SIGTERM',interrupted);}
