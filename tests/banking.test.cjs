const assert=require('node:assert/strict');
(async()=>{
const {normalize,reference,fetchPages}=await import('../banking/transactions.mjs');
const start='2026-10-03T16:40:00Z',a={label:'Sabadell',identification_hash:'A'},b={label:'Revolut',identification_hash:'B'};
const tx={entry_reference:'same',status:'BOOK',transaction_date:'2026-10-03',transaction_amount:{amount:'12.10',currency:'EUR'},credit_debit_indicator:'DBIT',creditor:{name:'Tienda'}};
assert.equal(normalize(tx,a,start).t,'g');assert.equal(normalize(tx,a,start).a,12.1);
assert.equal(normalize({...tx,credit_debit_indicator:'CRDT',debtor:{name:'Ingreso'}},b,start).t,'i');
assert.equal(normalize({...tx,transaction_date:'2026-10-02'},a,start),null);
assert.equal(normalize({...tx,transaction_date:'2026-10-03T10:00:00Z'},a,start),null);
assert.equal(normalize({...tx,status:'PDNG'},a,start),null);
assert.equal(normalize({...tx,transaction_amount:{amount:'2',currency:'USD'}},a,start),null);
assert.equal(normalize({...tx,transaction_amount:{amount:'NaN',currency:'EUR'}},a,start),null);
assert.notEqual(await reference(a,tx),await reference(b,tx));assert.equal(await reference(a,tx),await reference(a,{...tx,transaction_amount:{amount:'50',currency:'EUR'}}));
assert.equal(await reference(a,{...tx,entry_reference:null}),null);
const calls=[];assert.equal((await fetchPages(async p=>{calls.push(p);return p.continuation_key?{transactions:[tx]}:{transactions:[tx],continuation_key:'next'}},{date_from:'2026-10-03'})).length,2);assert.equal(calls[1].continuation_key,'next');
await assert.rejects(fetchPages(async()=>({transactions:[],continuation_key:'same'}),{}),/REPEATED/);
const baseline=new Set([await reference(a,tx)]);assert(baseline.has(await reference(a,tx)));assert(!baseline.has(await reference(b,tx)));
console.log('Banking: 14 checks passed, including no history, account separation, pending entries and pagination.');
})().catch(e=>{console.error(e);process.exitCode=1});
