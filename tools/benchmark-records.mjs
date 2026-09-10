import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { run } from '../web/engine.mjs';
const request={seed:20260911,count:10000,columns:[
  {name:'id',provider:'sequence'},{name:'name',provider:'name'},
  {name:'uuid',provider:'uuid4'},{name:'email',provider:'email'},
  {name:'date',provider:'date'},{name:'amount',provider:'decimal',min:0,max:100000,places:2},
]};
const start=performance.now();
const output=run(JSON.stringify(request));
const milliseconds=performance.now()-start;
assert(!output.startsWith('ERROR:'),output);
assert.equal(JSON.parse(output).length,request.count);
const report={date:new Date().toISOString(),node:process.version,platform:process.platform,arch:process.arch,
  rows:request.count,columns:request.columns.length,milliseconds:Math.round(milliseconds),
  utf8Bytes:Buffer.byteLength(output),outputSha256:createHash('sha256').update(output).digest('hex'),
  engineSha256:createHash('sha256').update(await readFile(new URL('../web/engine.mjs',import.meta.url))).digest('hex'),
  scope:'One local cold measurement including request decoding, generation and JSON rendering. No throughput or memory guarantee.'};
await writeFile(new URL('../evidence/records-benchmark.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
