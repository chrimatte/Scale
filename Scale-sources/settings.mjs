import {existsSync,readFileSync,writeFileSync,renameSync,unlinkSync,chmodSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

export function validateSettings(input, now=new Date()) {
  const fail=message=>{throw Error(message);};
  const number=(value,min,max,label)=>{const n=Number(String(value).replace(',','.'));if(!Number.isFinite(n)||n<min||n>max)fail(label);return n;};
  const name=String(input.name??'').trim();if(!name||name.length>80)fail('Enter a name of up to 80 characters.');
  const height=number(input.height,80,250,'Enter a height between 80 and 250 cm.');
  const weight=number(input.weight,20,250,'Enter a weight between 20 and 250 kg.');
  const birthDate=String(input.birthDate??'');
  const parsed=new Date(birthDate+'T00:00:00Z');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(birthDate)||!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,10)!==birthDate||parsed>now)fail('Enter a valid date of birth that is not in the future.');
  if(!['male','female'].includes(input.gender))fail('Select the sex used in your Renpho profile.');
  const athleteId=String(input.athleteId??'').trim();if(!/^i\d+$/.test(athleteId))fail('Athlete ID must use the format i123456.');
  const scaleId=String(input.scaleId??'').trim();
  if(scaleId&&!/^(?:[a-f\d]{32}|[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}|(?:[a-f\d]{2}:){5}[a-f\d]{2})$/i.test(scaleId))fail('Invalid Bluetooth identifier. Keep the identifier detected for your scale.');
  const apiKey=String(input.apiKey??'').trim();if(apiKey&&!/^[a-zA-Z0-9_-]+$/.test(apiKey))fail('The API key contains invalid characters. Copy it from Intervals.icu.');
  return {name,height,weight,birthDate,gender:input.gender,isAthlete:input.isAthlete===true,athleteId,scaleId,apiKey};
}
export async function settingsAction(root,action,input,request=fetch) {
  const yaml=await import(pathToFileURL(join(root,'node_modules/yaml/dist/index.js')));
  const dotenv=createRequire(join(root,'package.json'))('dotenv');
  const configPath=join(root,'config.yaml'),envPath=join(root,'.env');
  const original=readFileSync(configPath,'utf8');const raw=yaml.parse(original);
  const index=raw.users.findIndex(u=>u.exporters?.some(e=>e.type==='intervals'));
  if(index<0)throw Error('No Intervals.icu profile found in the configuration.');
  const user=raw.users[index];const entry=user.exporters.find(e=>e.type==='intervals');
  const envOriginal=existsSync(envPath)?readFileSync(envPath,'utf8'):'';
  const env=dotenv.parse(envOriginal);
  const existing=entry.api_key==='${INTERVALS_API_KEY}'?env.INTERVALS_API_KEY:entry.api_key;
  if(action==='settings-read')return {type:'settings',name:user.name,height:user.height,birthDate:user.birth_date,gender:user.gender,isAthlete:user.is_athlete,weight:user.last_known_weight??70,athleteId:entry.athlete_id,scaleId:raw.ble?.scale_mac??'',hasKey:typeof existing==='string'&&existing.length>0};
  const lock=join(root,'..','work','mac-app','measurement.lock');
  if(existsSync(lock)){
    const pid=Number(readFileSync(lock,'utf8'));let active=false;
    if(Number.isInteger(pid)&&pid>0)try{process.kill(pid,0);active=true;}catch(error){if(error.code!=='ESRCH')active=true;}
    if(active)throw Error('Stop the current weigh-in before saving settings.');
  }
  const value=validateSettings(input);
  const key=value.apiKey||existing;
  if(typeof key!=='string'||!key)throw Error('Enter your Intervals.icu API key.');
  if(!/^[a-zA-Z0-9_-]+$/.test(key))throw Error('The saved API key is invalid. Enter it again.');
  // Validate credentials with a read-only request before modifying either file.
  const response=await request('https://intervals.icu/api/v1/athlete/'+encodeURIComponent(value.athleteId),{
    headers:{Authorization:'Basic '+btoa('API_KEY:'+key)},signal:AbortSignal.timeout(10000)
  });
  if(response.status===401||response.status===403||response.status===404)throw Error('Invalid athlete ID or API key. No changes saved.');
  if(!response.ok)throw Error('Intervals.icu is unavailable. No changes saved.');
  const profile=await response.json();
  if(!profile||typeof profile!=='object'||Array.isArray(profile))throw Error('Invalid response from Intervals.icu. No changes saved.');
  // Re-read before committing, so a concurrent edit never gets overwritten.
  if(readFileSync(configPath,'utf8')!==original||(existsSync(envPath)?readFileSync(envPath,'utf8'):'')!==envOriginal)throw Error('The configuration has changed. Reopen settings and try again.');
  Object.assign(user,{name:value.name,height:value.height,birth_date:value.birthDate,gender:value.gender,is_athlete:value.isAthlete,last_known_weight:value.weight});
  if(value.weight<user.weight_range.min||value.weight>user.weight_range.max)user.weight_range={min:Math.max(20,value.weight-15),max:Math.min(250,value.weight+15)};
  Object.assign(entry,{athlete_id:value.athleteId,api_key:'${INTERVALS_API_KEY}'});
  raw.ble={...raw.ble,scale_mac:value.scaleId||null};
  const nextEnv=envOriginal.split(/\r?\n/).filter(line=>!/^\s*(?:export\s+)?INTERVALS_API_KEY\s*=/.test(line));
  while(nextEnv.at(-1)==='')nextEnv.pop();
  nextEnv.push("INTERVALS_API_KEY='"+key+"'");
  const suffix='.scale-'+process.pid+'.tmp';const configTmp=configPath+suffix,envTmp=envPath+suffix;
  try {
    writeFileSync(configTmp,yaml.stringify(raw),{mode:0o600,flag:'wx'});
    writeFileSync(envTmp,nextEnv.join('\n')+'\n',{mode:0o600,flag:'wx'});
    renameSync(envTmp,envPath);
    try{renameSync(configTmp,configPath);}catch(error){writeFileSync(envPath,envOriginal,{mode:0o600});throw error;}
    chmodSync(configPath,0o600);chmodSync(envPath,0o600);
  } finally {for(const path of [configTmp,envTmp])try{unlinkSync(path);}catch{}}
  return {type:'settings-saved',message:'Settings saved. Intervals.icu connection verified.'};
}
