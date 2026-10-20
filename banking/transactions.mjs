// Shared by the server worker and offline tests. No banking credentials here.
export async function reference(account, tx) {
  if (typeof tx.entry_reference !== 'string' || !tx.entry_reference.trim()) return null;
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(account.identification_hash+'\n'+tx.entry_reference));
  return Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
}
export function normalize(tx, account, startedAt) {
  if(tx.status!=='BOOK')return null;
  const date=tx.transaction_date||tx.booking_date||tx.value_date;
  if(typeof date!=='string'||!/^\d{4}-\d{2}-\d{2}(?:T.*)?$/.test(date)||!Number.isFinite(Date.parse(date)))return null;
  if(date.slice(0,10)<startedAt.slice(0,10))return null;
  if(date.includes('T')&&Date.parse(date)<Date.parse(startedAt))return null;
  if(tx.transaction_amount?.currency!=='EUR'||!['CRDT','DBIT'].includes(tx.credit_debit_indicator))return null;
  const raw=String(tx.transaction_amount.amount);
  if(!/^-?\d+(?:\.\d{1,2})?$/.test(raw))return null;
  const amount=Math.abs(Number(raw));
  if(!Number.isFinite(amount)||amount<=0||amount>1000000000)return null;
  const income=tx.credit_debit_indicator==='CRDT';
  const party=(income?tx.debtor?.name:tx.creditor?.name);
  const remittance=Array.isArray(tx.remittance_information)?tx.remittance_information.filter(x=>typeof x==='string').join(' '):'';
  return {ts:date.length===10?date+'T12:00:00Z':new Date(date).toISOString(),t:income?'i':'g',a:amount,m:String(party||remittance||'Movimiento bancario').slice(0,500),c:income?'Ingresos':'Sin clasificar',k:account.label,nt:remittance.slice(0,1000)};
}
export async function fetchPages(fetchPage, params) {
  const entries=[];let continuation;const seen=new Set();
  for(let page=0;page<100;page++) {
    const result=await fetchPage({...params,...(continuation?{continuation_key:continuation}:{})});
    if(!Array.isArray(result.transactions))throw new Error('INVALID_BANK_RESPONSE');
    entries.push(...result.transactions);
    if(!result.continuation_key)return entries;
    if(seen.has(result.continuation_key))throw new Error('REPEATED_CONTINUATION');
    continuation=result.continuation_key;seen.add(continuation);
  }
  throw new Error('TOO_MANY_PAGES');
}
