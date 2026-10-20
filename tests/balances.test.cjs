const assert=require('node:assert/strict');
(async()=>{
 const {selectBalance}=await import('../banking/balances.mjs');
 const b=(type,amount,currency='EUR',date=null)=>({balance_type:type,balance_amount:{amount,currency},reference_date:date});
 const pick=rows=>selectBalance({balances:rows});
 assert.equal(pick([b('CLBD','200.00'),b('ITAV','180.23')]).amount,180.23,'disponible prevalece sobre contabilizado');
 assert.equal(pick([b('CLBD','104.36'),b('XPCD','104.36')]).balance_type,'XPCD','respuesta Sabadell no suma dos saldos');
 assert.equal(pick([b('ITAV','286.56')]).amount,286.56,'respuesta Revolut');
 assert.equal(pick([b('ITAV','0')]).amount,0,'cero real es válido');
 assert.equal(pick([b('ITAV','-7.23')]).amount,-7.23,'saldo negativo conserva signo');
 assert.equal(pick([b('ITAV','200','USD'),b('ITBD','22.12')]).amount,22.12,'solo EUR');
 for(const rows of [[],[b('OPBD','200')],[b('INFO','300')],[b('FWAV','400')],[b('ITAV',null)],[b('ITAV','')],[b('ITAV','NaN')],[b('ITAV','12.123')],[b('ITAV','200','USD')]])assert.throws(()=>pick(rows),/BALANCE_UNAVAILABLE/);
 assert.throws(()=>selectBalance({}),/INVALID_BALANCE_RESPONSE/);
 assert.throws(()=>pick([b('ITAV','100'),b('ITAV','200')]),/AMBIGUOUS_BALANCE/,'no elige arbitrariamente dos cuentas');
 assert.equal(pick([b('ITAV','100','EUR','2026-10-14'),b('ITAV','120','EUR','2026-10-15')]).amount,120,'misma clase prefiere referencia reciente');
 console.log('Selección de saldo bancario: correctas (prioridad, céntimos, cero, negativo, moneda y respuestas incompletas).');
})().catch(e=>{console.error(e);process.exitCode=1});
