import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {spawn} from 'node:child_process';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
const bridge=fileURLToPath(new URL('./bridge.mjs',import.meta.url));
function fixture(t,{wrongWeight=false}={}){
 const dir=mkdtempSync(join(tmpdir(),'scale-bridge-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));const root=join(dir,'repo');
 for(const path of ['dist/config','node_modules/yaml/dist'])mkdirSync(join(root,path),{recursive:true});
 writeFileSync(join(root,'package.json'),JSON.stringify({type:'module'}));
 const config={users:[{slug:'atleta',exporters:[{type:'intervals',athlete_id:'i-test',api_key:'test-secret-never-log'}]}],runtime:{continuous_mode:true},global_exporters:[]};
 writeFileSync(join(root,'dist/config/load.js'),`export const loadAppConfig=()=>({config:${JSON.stringify(config)}});`);
 writeFileSync(join(root,'config.yaml'),JSON.stringify(config));
 writeFileSync(join(root,'node_modules/yaml/dist/index.js'),'export const parse=JSON.parse;export const stringify=JSON.stringify;');
 writeFileSync(join(root,'dist/index.js'),`console.log('[Sync] Measurement: 71.90 kg / 0 Ohm');console.log('[Sync]   bodyFatPercent: 13.02');console.log('[Intervals] Intervals.icu wellness updated for 2026-11-05.');setInterval(()=>{},1000);`);
 const mock=join(dir,'network.mjs');
 writeFileSync(mock,`globalThis.fetch=async url=>({ok:true,status:200,json:async()=>String(url).includes('/wellness/')?{weight:${wrongWeight?70:71.9},bodyFat:13}:{timezone:'Europe/Rome'}});`);
 return {root,dir,mock};
}
async function run(f,extra=[]){
 const child=spawn(process.execPath,['--import',f.mock,bridge,'--root',f.root,'--action','measure',...extra]);
 let out='',err='';child.stdout.on('data',d=>out+=d);child.stderr.on('data',d=>err+=d);
 const timer=setTimeout(()=>child.kill('SIGKILL'),10000);
 const code=await new Promise(r=>child.on('exit',r));clearTimeout(timer);
 assert.equal(err,'');assert.ok(!out.includes('test-secret-never-log'));
 return {code,events:out.trim().split('\n').map(JSON.parse)};
}
test('weight-only config, independent verification and Bluetooth cleanup',async t=>{
 const f=fixture(t);const r=await run(f);assert.equal(r.code,0);
 const final=r.events.at(-1);assert.equal(final.type,'success');assert.equal(final.weight,71.9);assert.equal(final.bodyFat,null);
 const path=join(f.dir,'work/mac-app/config.yaml');const c=JSON.parse(readFileSync(path));
 assert.equal(c.users[0].estimate_body_composition,false);assert.equal(c.runtime.continuous_mode,false);assert.equal(c.runtime.retry_failed_exports,false);
 assert.equal(c.users[0].exporters[0].api_key,'${INTERVALS_API_KEY}');
 assert.ok(!existsSync(join(f.dir,'work/mac-app/measurement.lock')));
});
test('estimated fat is exported only with explicit option',async t=>{
 const f=fixture(t);const r=await run(f,['--estimate']);assert.equal(r.code,0);assert.equal(r.events.at(-1).bodyFat,13);
 assert.equal(JSON.parse(readFileSync(join(f.dir,'work/mac-app/config.yaml'))).users[0].estimate_body_composition,true);
});
test('server mismatch never reports success',async t=>{
 const f=fixture(t,{wrongWeight:true});const r=await run(f);assert.equal(r.code,1);assert.equal(r.events.at(-1).type,'error');
 assert.ok(!r.events.some(e=>e.type==='success'));
});
test('cancel stops the reader and releases the measurement lock',async t=>{
 const f=fixture(t);
 writeFileSync(join(f.root,'dist/index.js'),`import {writeFileSync} from 'node:fs';writeFileSync('child.pid',String(process.pid));setInterval(()=>{},1000);`);
 const child=spawn(process.execPath,['--import',f.mock,bridge,'--root',f.root,'--action','measure']);
 let out='';child.stdout.on('data',d=>out+=d);
 const timer=setTimeout(()=>child.kill('SIGKILL'),10000);
 for(let i=0;i<100&&!existsSync(join(f.root,'child.pid'));i++)await new Promise(r=>setTimeout(r,20));
 assert.ok(existsSync(join(f.root,'child.pid')));
 const exit=new Promise(r=>child.on('exit',r));child.kill('SIGTERM');assert.equal(await exit,0);clearTimeout(timer);
 assert.ok(!existsSync(join(f.dir,'work/mac-app/measurement.lock')));
 const pid=Number(readFileSync(join(f.root,'child.pid')));assert.throws(()=>process.kill(pid,0),{code:'ESRCH'});
 assert.ok(!out.includes('"type":"success"'));
});
