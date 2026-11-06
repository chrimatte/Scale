import {readFileSync, writeFileSync, mkdirSync, openSync, closeSync, unlinkSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {parseLine, verifyReading, dayInZone} from './core.mjs';
const args = process.argv.slice(2);
const option = name => args[args.indexOf(name) + 1];
const root = resolve(option('--root'));
const estimate = args.includes('--estimate');
const emit = event => process.stdout.write(JSON.stringify(event) + '\n');
let child, lockPath, lockOwned=false, closing=false, finished=false, buffer='', weight=null, bodyFat=null;
const stop = async () => {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  const processToStop=child;
  await new Promise(resolve => {
    const timer=setTimeout(() => {processToStop.kill('SIGKILL');}, 2000);
    processToStop.once('exit', () => {clearTimeout(timer); resolve();});
    processToStop.kill('SIGINT');
  });
};
const releaseLock=()=> {if(lockOwned){try{unlinkSync(lockPath);}catch{}lockOwned=false;}};
process.on('exit', releaseLock);
for (const signal of ['SIGTERM','SIGINT']) process.on(signal, async () => {
  if(closing)return;closing=true; await stop(); releaseLock(); process.exit(0);
});
try {
  process.chdir(root);
  // Keep library diagnostics out of the structured UI channel. Never print secrets.
  console.log=()=>{};console.info=()=>{};console.warn=()=>{};console.error=()=>{};
  const action=option('--action');
  if(action==='settings-read'||action==='settings-save') {
    const {settingsAction}=await import('./settings.mjs');
    let input={};
    if(action==='settings-save') {
      let data='';for await(const chunk of process.stdin){data+=chunk;if(data.length>16000)throw Error('Settings data is too long.');}
      try{input=JSON.parse(data);}catch{throw Error('Invalid settings data.');}
    }
    emit(await settingsAction(root,action,input));process.exit(0);
  }
  const {loadAppConfig}=await import(pathToFileURL(join(root,'dist/config/load.js')));
  const {config}=loadAppConfig();
  const user=config.users.find(u=>u.exporters?.some(e=>e.type==='intervals'));
  const entry=user?.exporters.find(e=>e.type==='intervals');
  if(!entry?.api_key) throw Error('Intervals.icu API key is missing. Complete the initial connection setup.');
  const base='https://intervals.icu/api/v1/athlete/'+encodeURIComponent(entry.athlete_id);
  const headers={Authorization:'Basic '+btoa('API_KEY:'+entry.api_key)};
  const get=async path=>{
    const response=await fetch(base+path,{headers,signal:AbortSignal.timeout(10000)});
    if(response.status===401||response.status===403)throw Error('Intervals.icu API key is invalid or lacks access.');
    if(!response.ok)throw Error('Intervals.icu is unavailable (HTTP '+response.status+'). Try again.');
    return response.json();
  };
  emit({type:'status',stage:'checking',message:'Checking the connection…'});
  const profile=await get('');
  const date=dayInZone(profile.timezone||'Europe/Rome');
  const today=await get('/wellness/'+date);
  emit({type:'connected',athlete:entry.athlete_id,date,weight:today.weight??null,bodyFat:today.bodyFat??null});
  if(option('--action')==='check') process.exit(0);
  const stateDir=join(root,'..','work','mac-app');mkdirSync(stateDir,{recursive:true,mode:0o700});
  lockPath=join(stateDir,'measurement.lock');
  const acquire=()=>{const fd=openSync(lockPath,'wx',0o600);writeFileSync(fd,String(process.pid));closeSync(fd);lockOwned=true;};
  try{acquire();}catch(error){
    if(error.code!=='EEXIST')throw error;
    let stale=false;
    try{const pid=Number(readFileSync(lockPath,'utf8'));if(!Number.isInteger(pid)||pid<=0)stale=true;else{try{process.kill(pid,0);}catch(e){if(e.code==='ESRCH')stale=true;}}}catch{}
    if(stale){try{unlinkSync(lockPath);acquire();}catch{throw Error('Could not start a new weigh-in. Try again.');}}
    else throw Error('A weigh-in is already in progress. Close the other window and try again.');
  }
  const yaml=await import(pathToFileURL(join(root,'node_modules/yaml/dist/index.js')));
  const raw=yaml.parse(readFileSync(join(root,'config.yaml'),'utf8'));
  raw.users=[{...raw.users.find(u=>u.slug===user.slug),estimate_body_composition:estimate,exporters:[entry]}];
  // The only secret remains an environment reference in the app configuration.
  raw.users[0].exporters=[{type:'intervals',athlete_id:entry.athlete_id,api_key:'${INTERVALS_API_KEY}'}];
  process.env.INTERVALS_API_KEY=entry.api_key;
  raw.global_exporters=[];
  raw.runtime={...raw.runtime,continuous_mode:false,retry_failed_exports:false,dry_run:false,debug:false};
  raw.update_check=false;
  const configPath=join(stateDir,'config.yaml');writeFileSync(configPath,yaml.stringify(raw),{mode:0o600});
  emit({type:'status',stage:'scanning',message:'Looking for your Renpho. Tap the scale to wake it up.'});
  child=spawn(process.execPath,[join(root,'dist/index.js'),'--config',configPath],{
    cwd:root,env:{...process.env,CONTINUOUS_MODE:'false',TZ:'Europe/Rome'},stdio:['ignore','pipe','pipe']
  });
  const fail=async message=>{
    if(finished||closing)return;finished=true;await stop();releaseLock();emit({type:'error',message});process.exit(1);
  };
  const consume=async line=>{
    if(finished||closing)return;
    const event=parseLine(line);
    if(!event)return;
    if(event.type==='measurement'){weight=event.weight;emit(event);return;}
    if(event.type==='fat'){bodyFat=event.bodyFat;return;}
    if(event.type!=='uploaded'){emit(event);return;}
    finished=true;
    try{
      emit({type:'status',stage:'verifying',message:'Upload complete. Verifying the saved data…'});
      const actual=await get('/wellness/'+event.date);
      if(!verifyReading(actual,weight,bodyFat,estimate))throw Error('Upload completed, but the values read back do not match. Check Intervals.icu.');
      await stop();releaseLock();
      emit({type:'success',weight:actual.weight,bodyFat:estimate?actual.bodyFat:null,date:event.date,estimated:estimate});
      process.exit(0);
    }catch(error){await stop();releaseLock();emit({type:'error',message:error.message});process.exit(1);}
  };
  child.stdout.on('data',data=>{
    buffer+=data.toString();const lines=buffer.split(/[\r\n]+/);buffer=lines.pop();
    for(const line of lines)void consume(line);
  });
  child.stderr.on('data',()=>{});
  child.on('error',()=>void fail('Could not start reading the scale.'));
  child.on('exit',code=>{
    if(!finished&&!closing)void fail(code===0?'No weigh-in recorded. Wake up the scale and try again.':'Reading interrupted. Check Bluetooth, move closer and close Renpho on your phone.');
  });
  setTimeout(()=>void fail('Timed out. Move your Mac closer, close Renpho on your phone and try again.'),150000).unref();
}catch(error){await stop();releaseLock();emit({type:'error',message: /fetch|network|ENOTFOUND/i.test(error.message)?'No Internet connection. Check your network and try again.':error.message});process.exit(1);}
