import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,symlinkSync,rmSync,statSync} from 'node:fs';
import {join} from 'node:path';
import {settingsAction,validateSettings} from './settings.mjs';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
const modules=fileURLToPath(new URL('../ble-scale-sync/node_modules/',import.meta.url));
const value={name:'Atleta',height:'183',weight:'71,9',birthDate:'2001-04-07',gender:'male',isAthlete:true,athleteId:'i204570',apiKey:'',scaleId:'c7d9a1b07ac3c695700cd2158bcfa02c'};
const ok=async()=>({ok:true,status:200,json:async()=>({id:'i204570',timezone:'Europe/Rome'})});
function fixture(t){
 const dir=mkdtempSync(join(tmpdir(),'scale-settings-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
 const root=join(dir,'repo');mkdirSync(join(root,'node_modules'),{recursive:true});
 for(const module of ['yaml','dotenv'])symlinkSync(join(modules,module),join(root,'node_modules',module));
 const raw={version:1,ble:{handler:'auto',scale_mac:value.scaleId},users:[{name:'Prima',slug:'atleta',height:180,birth_date:'2001-04-07',gender:'male',is_athlete:false,last_known_weight:70,weight_range:{min:55,max:85},exporters:[{type:'intervals',athlete_id:'i204570',api_key:'${INTERVALS_API_KEY}'}]}],runtime:{continuous_mode:true},global_exporters:[]};
 writeFileSync(join(root,'config.yaml'),JSON.stringify(raw));writeFileSync(join(root,'.env'),"OTHER_SETTING=keep\nINTERVALS_API_KEY='old-test-key'\n");
 return {root,dir,beforeConfig:readFileSync(join(root,'config.yaml'),'utf8'),beforeEnv:readFileSync(join(root,'.env'),'utf8')};
}
test('read prefills profile without exposing saved API key',async t=>{
 const f=fixture(t);const r=await settingsAction(f.root,'settings-read');
 assert.equal(r.name,'Prima');assert.equal(r.hasKey,true);assert.ok(!JSON.stringify(r).includes('old-test-key'));assert.ok(!Object.hasOwn(r,'apiKey'));
});
test('save validates authentication, preserves key when blank, and protects files',async t=>{
 const f=fixture(t);let auth;
 const r=await settingsAction(f.root,'settings-save',value,async(url,options)=>{auth=options.headers.Authorization;return ok();});
 assert.equal(r.type,'settings-saved');assert.equal(auth,'Basic '+btoa('API_KEY:old-test-key'));
 const env=readFileSync(join(f.root,'.env'),'utf8');assert.ok(env.includes('old-test-key'));assert.ok(env.includes('OTHER_SETTING=keep'));
 const yaml=await import('../ble-scale-sync/node_modules/yaml/dist/index.js');const c=yaml.parse(readFileSync(join(f.root,'config.yaml'),'utf8'));
 assert.equal(c.users[0].height,183);assert.equal(c.users[0].is_athlete,true);assert.equal(c.users[0].last_known_weight,71.9);assert.equal(c.runtime.continuous_mode,true);
 assert.equal(statSync(join(f.root,'.env')).mode&0o777,0o600);assert.equal(statSync(join(f.root,'config.yaml')).mode&0o777,0o600);
});
test('new API key replaces the old key only after successful authentication',async t=>{
 const f=fixture(t);await settingsAction(f.root,'settings-save',{...value,apiKey:'new-test-key'},ok);
 const env=readFileSync(join(f.root,'.env'),'utf8');assert.ok(env.includes('new-test-key'));assert.ok(!env.includes('old-test-key'));
});
test('invalid credentials leave both files untouched',async t=>{
 const f=fixture(t);await assert.rejects(settingsAction(f.root,'settings-save',{...value,apiKey:'wrong-key'},async()=>({ok:false,status:401})),/Nessuna modifica/);
 assert.equal(readFileSync(join(f.root,'config.yaml'),'utf8'),f.beforeConfig);assert.equal(readFileSync(join(f.root,'.env'),'utf8'),f.beforeEnv);
});
test('invalid profile cannot trigger network or save',async t=>{
 const f=fixture(t);await assert.rejects(settingsAction(f.root,'settings-save',{...value,birthDate:'2001-02-30'},()=>{throw Error('should never request');}),/data di nascita/);
 assert.equal(readFileSync(join(f.root,'config.yaml'),'utf8'),f.beforeConfig);
 assert.throws(()=>validateSettings({...value,height:'NaN'}),/altezza/);
 assert.throws(()=>validateSettings({...value,athleteId:'wrong'}),/ID atleta/);
 assert.throws(()=>validateSettings({...value,apiKey:"x'\nOTHER=bad"}),/chiave API/);
});
test('connection failure leaves the existing configuration intact',async t=>{
 const f=fixture(t);await assert.rejects(settingsAction(f.root,'settings-save',value,async()=>{throw Error('network unavailable');}));
 assert.equal(readFileSync(join(f.root,'config.yaml'),'utf8'),f.beforeConfig);assert.equal(readFileSync(join(f.root,'.env'),'utf8'),f.beforeEnv);
});
