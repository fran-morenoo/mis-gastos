const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const {reference,normalize,fetchPages}=await import('../banking/transactions.mjs');
 const {selectBalance}=await import('../banking/balances.mjs');
 const key=crypto.generateKeyPairSync('rsa',{modulusLength:2048}).privateKey.export({type:'pkcs8',format:'pem'});
 const cfg={privateKey:key,appId:'test-only',syncToken:'a'.repeat(64),started_at:'2026-10-03T16:54:09Z',accounts:[{uid:'test-s',label:'Sabadell',identification_hash:'s'},{uid:'test-r',label:'Revolut',identification_hash:'r'}]};
 let handler,calls,mode='ok';
 const Deno={env:{get:n=>n==='SUPABASE_URL'?'https://db.invalid':n==='SUPABASE_SERVICE_ROLE_KEY'?'test-only':''},serve:h=>handler=h};
 const json=(v,status=200)=>new Response(JSON.stringify(v),{status});
 const fetch=async(url,opts)=>{
  calls.push({url,body:opts?.body&&JSON.parse(opts.body)});
  if(url.endsWith('/rpc/bank_sync_worker')){const {p_action}=JSON.parse(opts.body);if(p_action==='config')return json(cfg);if(p_action==='acquire')return json({lease:'lease-test'});if(p_action==='commit')return json({inserted:1});return json({ok:true});}
  if(url.includes('/transactions?')){if(mode==='tx-fails'&&url.includes('test-s'))return json({},429);return json({transactions:[{entry_reference:'only-one',status:'BOOK',booking_date:'2026-10-15',credit_debit_indicator:'DBIT',transaction_amount:{currency:'EUR',amount:'5.00'}}]});}
  if(url.endsWith('/balances')){if(mode==='balance-fails'&&url.includes('test-s'))return json({},429);if(mode==='empty-balance')return json({balances:[]});return json({balances:[{balance_type:'ITAV',balance_amount:{currency:'EUR',amount:'286.56'}}]});}
  throw new Error('unexpected call');
 };
 let src=fs.readFileSync(require('node:path').join(__dirname,'../banking/index.ts'),'utf8').replace(/^import .*;\n/gm,'');
 src=require('node:module').stripTypeScriptTypes(src);
 new Function('Deno','fetch','reference','normalize','fetchPages','selectBalance','crypto',src)(Deno,fetch,reference,normalize,fetchPages,selectBalance,crypto.webcrypto);
 async function execute(testMode,token=cfg.syncToken){mode=testMode;calls=[];return handler(new Request('https://worker.invalid',{method:'POST',headers:{'X-Bank-Sync-Token':token},body:'{}'}));}
 assert.equal((await execute('ok','0'.repeat(64))).status,401);assert.equal(calls.filter(c=>c.url.includes('api.enablebanking')).length,0,'token inválido no consulta banco');
 assert.equal((await execute('ok')).status,200);
 assert.equal(calls.filter(c=>c.body?.p_action==='balance').length,2,'persiste ambos saldos');
 assert.equal(calls.filter(c=>c.body?.p_action==='commit').length,2,'movimientos continúan importándose');
 assert.equal(calls.some(c=>c.body?.p_action==='balance'&&c.body.p_data.amount===286.56),true);
 assert.equal(JSON.stringify(calls.find(c=>c.body?.p_action==='release').body).includes('286.56'),false,'logs del resultado sin importes');
 assert.equal((await execute('tx-fails')).status,502);
 assert.equal(calls.filter(c=>c.body?.p_action==='balance').length,2,'fallo de movimientos no bloquea saldo');
 assert.equal((await execute('balance-fails')).status,502);
 assert.equal(calls.filter(c=>c.body?.p_action==='commit').length,2,'fallo de saldo no bloquea movimientos');
 assert.equal(calls.filter(c=>c.body?.p_action==='balance').length,1,'el otro banco se actualiza');
 assert.equal((await execute('empty-balance')).status,502);
 assert.equal(calls.filter(c=>c.body?.p_action==='balance').length,0,'sin saldo válido no sobreescribe anterior');
 assert.equal(calls.at(-1).body.p_action,'release','libera bloqueo tras fallo');
 console.log('Worker: autenticación, saldos/movimientos independientes, respuestas vacías y privacidad del resultado: correctos.');
})().catch(e=>{console.error(e);process.exitCode=1});
