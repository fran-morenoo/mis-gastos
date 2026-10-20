// Prefer money available now. Never sum alternative representations of one balance.
export function selectBalance(data) {
  if (!Array.isArray(data?.balances)) throw new Error('INVALID_BALANCE_RESPONSE');
  const priority = ['ITAV', 'XPCD', 'CLAV', 'ITBD', 'CLBD'];
  const candidates = data.balances.filter(b => priority.includes(b?.balance_type)
    && b.balance_amount?.currency === 'EUR'
    && /^-?\d+(?:\.\d{1,2})?$/.test(String(b.balance_amount.amount))
    && Number.isFinite(Number(b.balance_amount.amount))
    && Math.abs(Number(b.balance_amount.amount)) <= 1e9
    && (!b.reference_date || (/^\d{4}-\d{2}-\d{2}$/.test(b.reference_date) && Number.isFinite(Date.parse(b.reference_date)))));
  if (!candidates.length) throw new Error('BALANCE_UNAVAILABLE');
  candidates.sort((a,b) => priority.indexOf(a.balance_type) - priority.indexOf(b.balance_type)
    || String(b.reference_date || '').localeCompare(String(a.reference_date || '')));
  const chosen = candidates[0];
  if (candidates.some(b => b.balance_type === chosen.balance_type && b.reference_date === chosen.reference_date
    && Number(b.balance_amount.amount) !== Number(chosen.balance_amount.amount))) throw new Error('AMBIGUOUS_BALANCE');
  return {amount: Number(chosen.balance_amount.amount), currency: 'EUR', balance_type: chosen.balance_type,
    reference_date: chosen.reference_date || null};
}
