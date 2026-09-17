import {parentPort} from 'node:worker_threads';
import {session} from '../web/engine.mjs';
let handle;
const call=command=>{const result=JSON.parse(session(JSON.stringify(command)));if(!result.ok)throw Error(result.error);return result};
parentPort.on('message',message=>{
 try{
  let result;
  if(message.op==='open'){if(handle)throw Error('Already open');const opened=call({op:'open',definition:message.definition});handle=opened.id;result={index:opened.index};}
  else if(message.op==='next'){
   if(!Number.isInteger(message.count)||message.count<1||message.count>256)throw Error('Batch size 1..256 required');
   const rows=[];let bytes=0,index,error;
   for(let i=0;i<message.count;i++){try{const next=call({op:'next',id:handle});rows.push(next.row);index=next.index;bytes+=Buffer.byteLength(JSON.stringify(next.row));if(bytes>=1048576)break;}catch(e){error=e.message;break;}}
   result={rows,index,error};
  }else if(message.op==='checkpoint')result=call({op:'checkpoint',id:handle}).checkpoint;
  else throw Error('Unknown worker operation');
  parentPort.postMessage({id:message.id,result});
 }catch(error){parentPort.postMessage({id:message.id,error:String(error.message||error)});}
});
