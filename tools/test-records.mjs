import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { run } from '../web/engine.mjs';
const column = (name, provider, options={}) => ({name,provider,...options});
const columns = [
  column('id','sequence',{start:1000,step:2,unique:true}), column('name','name'),column('address','address'),
  column('email','email'),column('username','username'),column('url','url'),column('uuid','uuid4',{unique:true}),
  column('ipv4','ipv4'),column('ipv6','ipv6'),column('mac','mac'),column('color','color'),
  column('company','company'),column('job','job'),column('word','word'),column('sentence','sentence',{words:3}),
  column('active','boolean',{percent:37}),column('quantity','integer',{min:1,max:9}),
  column('price','decimal',{min:-12500,max:30000,places:2}),column('date','date',{first:'2024-02-28',last:'2024-03-02'}),
  column('ean','ean13'),column('isbn','isbn13'),column('code','template',{template:'SKU-??-####'}),
  column('category','choice',{values:['A','B,quoted','C\nline']}),
  column('status','weighted_choice',{values:['unused','active','archived'],weights:[0,3,1]}),
  column('note','constant',{value:'a,"b"\r\nc'}),column('optional','constant',{value:'optional',null_percent:25}),
];
const schema = {seed:20260911,count:256,columns};
for (const format of ['json','jsonl','csv']) {
  const output = run(JSON.stringify({...schema,format}));
  assert(!output.startsWith('ERROR:'),output);
  await writeFile(new URL(`../evidence/records.${format}`,import.meta.url),output);
}
await writeFile(new URL('../evidence/records-schema.json',import.meta.url),JSON.stringify(schema,null,2)+'\n');
const errors = [
  {columns:[column('x','name',{unexpected:1})]},
  {columns:[column('x','choice',{values:[]})]},
  {count:2,columns:[column('x','constant',{value:1,unique:true})]},
  {columns:[column('x','weighted_choice',{values:['a'],weights:[0]})]},
  {columns:[column('x','date',{first:'1900-02-29'})]},
  {columns:[column('x','missing_provider')]},
  {columns:[column('x','integer',{min:5,max:1})]},
  {columns:[column('x','name',{null_percent:101})]},
  {seed:4294967296,columns:[column('x','name')]},
  {count:10001,columns:[column('x','name')]},
];
for (const input of errors) assert.match(run(JSON.stringify(input)),/^ERROR:/);
await mkdir(new URL('../examples/',import.meta.url),{recursive:true});
const example = {seed:42,count:5,columns:[column('id','sequence',{start:1}),column('customer','name'),column('price','decimal',{min:500,max:12000,places:2}),column('status','weighted_choice',{values:['new','shipped','cancelled'],weights:[5,4,1]}),column('reference','uuid4',{unique:true})]};
await writeFile(new URL('../examples/orders.json',import.meta.url),JSON.stringify(example,null,2)+'\n');
const cli=spawnSync(process.execPath,[fileURLToPath(new URL('./cli.mjs',import.meta.url)),'--file',fileURLToPath(new URL('../examples/orders.json',import.meta.url))],{encoding:'utf8',timeout:5000});
assert.equal(cli.status,0,cli.stderr); assert.equal(JSON.parse(cli.stdout).length,5);
const emptyCli=spawnSync(process.execPath,[fileURLToPath(new URL('./cli.mjs',import.meta.url)),'--input',JSON.stringify({...example,count:0,format:'jsonl'})],{encoding:'utf8',timeout:5000});
assert.equal(emptyCli.status,0,emptyCli.stderr); assert.equal(emptyCli.stdout,'');
const evidence = {date:new Date().toISOString(),node:process.version,rows:schema.count,columns:columns.length,formats:3,rejectedCases:errors.length,schemaFileCli:true,emptyJsonlCli:true,
  engineSha256:createHash('sha256').update(await readFile(new URL('../web/engine.mjs',import.meta.url))).digest('hex')};
await writeFile(new URL('../evidence/record-generation.json',import.meta.url),JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence));
