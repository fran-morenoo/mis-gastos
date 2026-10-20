import {reference,normalize,fetchPages} from './transactions.mjs';
import {selectBalance} from './balances.mjs';
const base=Deno.env.get('SUPABASE_URL');
let apiKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
try{apiKey=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||apiKey;}catch{}
async function rpc(action:string,data:unknown={}){
 const r=await fetch(base+'/rest/v1/rpc/bank_sync_worker',{method:'POST',headers:{apikey:apiKey,...(apiKey.startsWith('sb_')?{}:{Authorization:'Bearer '+apiKey}),'Content-Type':'application/json'},body:JSON.stringify({p_action:action,p_data:data}),signal:AbortSignal.timeout(20000)});
 if(!r.ok)throw new Error('DATABASE_HTTP_'+r.status);
 return await r.json();
}
const enc=new TextEncoder();
function b64(bytes:Uint8Array){let s='';for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');}
async function bankToken(cfg:any){
 const pem=cfg.privateKey.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
 const der=Uint8Array.from(atob(pem),c=>c.charCodeAt(0));
 const key=await crypto.subtle.importKey('pkcs8',der,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 const now=Math.floor(Date.now()/1000);
 const unsigned=b64(enc.encode(JSON.stringify({typ:'JWT',alg:'RS256',kid:cfg.appId})))+'.'+b64(enc.encode(JSON.stringify({iss:'enablebanking.com',aud:'api.enablebanking.com',iat:now,exp:now+300})));
 return unsigned+'.'+b64(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,enc.encode(unsigned))));
}
async function authenticate(actual:string,expected:string){
 const a=new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(actual)));
 const b=new Uint8Array(await crypto.subtle.digest('SHA-256',enc.encode(expected)));
 let diff=0;for(let i=0;i<a.length;i++)diff|=a[i]^b[i];return diff===0;
}
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 const token=req.headers.get('X-Bank-Sync-Token')||'';
 if(!/^[a-f0-9]{64}$/.test(token))return reply({error:'Unauthorized'},401);
 let lease:string|undefined;
 try{
  const cfg=await rpc('config');
  if(!await authenticate(token,cfg.syncToken))return reply({error:'Unauthorized'},401);
  let body:any={};try{body=await req.json();}catch{}
  if(body.check===true)return reply({ready:true,accounts:cfg.accounts.map((a:any)=>a.label),started_at:cfg.started_at});
  const acquired=await rpc('acquire');if(acquired.busy)return reply({busy:true});lease=acquired.lease;
  const auth=await bankToken(cfg),results=[];let success=true;
  const safeError=(e:unknown)=>{const message=String((e as Error).message);return /^(CONSENT_EXPIRED|BANK_HTTP_\d+|DATABASE_HTTP_\d+|INVALID_BANK_RESPONSE|REPEATED_CONTINUATION|TOO_MANY_PAGES|INVALID_BALANCE_RESPONSE|BALANCE_UNAVAILABLE|AMBIGUOUS_BALANCE|MULTIPLE_BANK_ACCOUNTS)$/.test(message)?message:'SYNC_FAILED'};
  for(const account of cfg.accounts){
   const result:any={bank:account.label};
   try{
    if(account.valid_until&&Date.parse(account.valid_until)<Date.now())throw new Error('CONSENT_EXPIRED');
    const since=new Date(Math.max(Date.parse(cfg.started_at),Date.parse(cfg.last_success||cfg.started_at)-7*86400000)).toISOString().slice(0,10);
    const txs=await fetchPages(async(p:any)=>{
     const r=await fetch('https://api.enablebanking.com/accounts/'+encodeURIComponent(account.uid)+'/transactions?'+new URLSearchParams(p),{headers:{Authorization:'Bearer '+auth,Accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(20000)});
     if(!r.ok)throw new Error('BANK_HTTP_'+r.status);return await r.json();
    },{date_from:since});
    const entries=[];let skipped=0;
    for(const tx of txs){const ref=await reference(account,tx),row=normalize(tx,account,cfg.started_at);if(!ref||!row){skipped++;continue;}entries.push({ref,...row,date:row.ts.slice(0,10)});}
    // Batches are atomic; seen references survive edits/deletions in the application.
    let inserted=0;for(let offset=0;offset<entries.length;offset+=200){const result=await rpc('commit',{lease,entries:entries.slice(offset,offset+200)});inserted+=result.inserted;}
    result.inserted=inserted;result.skipped=skipped;
   }catch(e){success=false;result.error=safeError(e);}
   // A transaction failure must not stop an independent balance refresh (or vice versa).
   try{
    if(account.valid_until&&Date.parse(account.valid_until)<Date.now())throw new Error('CONSENT_EXPIRED');
    if(cfg.accounts.filter((a:any)=>a.label===account.label).length!==1)throw new Error('MULTIPLE_BANK_ACCOUNTS');
    const r=await fetch('https://api.enablebanking.com/accounts/'+encodeURIComponent(account.uid)+'/balances',{headers:{Authorization:'Bearer '+auth,Accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(20000)});
    if(!r.ok)throw new Error('BANK_HTTP_'+r.status);
    const snapshot=selectBalance(await r.json());
    await rpc('balance',{lease,bank:account.label,...snapshot});result.balance_updated=true;
   }catch(e){success=false;result.balance_error=safeError(e);result.error=result.error||result.balance_error;}
   results.push(result);
  }
  await rpc('release',{lease,success,results});lease=undefined;
  return reply({success,results},success?200:502);
 }catch{
  if(lease)try{await rpc('release',{lease,success:false,error:'WORKER_FAILED'});}catch{}
  return reply({error:'Synchronization unavailable'},503);
 }
});
