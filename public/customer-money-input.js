/* Separadores de miles mientras se editan importes de facturas y recibos. */
(() => {
  function format(raw, cursor = String(raw).length, dotDecimal = true) {
    const text = String(raw ?? '');
    const comma = text.indexOf(',');
    const lastDot = text.lastIndexOf('.');
    const decimal = comma >= 0 ? comma : dotDecimal && lastDot >= 0 && /^\d[\d.]*$/.test(text.slice(0, lastDot)) && /^\d{0,2}$/.test(text.slice(lastDot + 1)) ? lastDot : -1;
    const integer = (decimal < 0 ? text : text.slice(0, decimal)).replace(/\D/g, '');
    const fraction = decimal < 0 ? '' : text.slice(decimal + 1).replace(/\D/g, '').slice(0, 2);
    const grouped = integer.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    const value = grouped + (decimal < 0 ? '' : ',' + fraction);
    const before = text.slice(0, Math.max(0, cursor));
    if (decimal >= 0 && cursor > decimal)
      return { value, cursor: grouped.length + 1 + Math.min(before.slice(decimal + 1).replace(/\D/g, '').length, fraction.length) };
    const digits = before.replace(/\D/g, '').length;
    if (!digits) return { value, cursor: 0 };
    let seen = 0;
    for (let i = 0; i < grouped.length; i++) if (/\d/.test(grouped[i]) && ++seen === digits) return { value, cursor: i + 1 };
    return { value, cursor: grouped.length };
  }

  function apply(input) {
    const result = format(input.value, input.selectionStart ?? input.value.length);
    input.value = result.value;
    input.setSelectionRange(result.cursor, result.cursor);
  }

  function erase(input, event) {
    if (event.key !== 'Backspace' && event.key !== 'Delete') return false;
    const start = input.selectionStart, end = input.selectionEnd;
    if (start == null || end == null) return false;
    let from = start, to = end;
    if (start === end) {
      if (event.key === 'Backspace') {
        if (start === 0) return false;
        from = input.value[start - 1] === '.' ? Math.max(0, start - 2) : start - 1;
      } else {
        if (start === input.value.length) return false;
        to = input.value[start] === '.' ? Math.min(input.value.length, start + 2) : start + 1;
      }
    }
    event.preventDefault();
    const raw = input.value.slice(0, from) + input.value.slice(to);
    const result = format(raw, from, false);
    input.value = result.value;
    input.setSelectionRange(result.cursor, result.cursor);
    input.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }

  const api = { format, apply, erase };
  if (typeof window !== 'undefined') window.customerMoneyInput = api;
  if (typeof module !== 'undefined') module.exports = api;
})();
