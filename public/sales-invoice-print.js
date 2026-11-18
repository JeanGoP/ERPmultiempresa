/* Impresión de la venta guardada y sus unidades serializadas. */
(() => {
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  })[char]);
  const amount = value => new Intl.NumberFormat('es-CO', {
    minimumFractionDigits:2, maximumFractionDigits:2
  }).format(Number(value) || 0);
  const quantity = value => new Intl.NumberFormat('es-CO', { maximumFractionDigits:6 }).format(Number(value) || 0);
  const round = value => Math.round((value + Number.EPSILON) * 100) / 100;
  const date = value => {
    const parts = String(value || '').slice(0, 10).split('-');
    return parts.length === 3 ? parts.reverse().join('/') : '—';
  };
  const timestamp = value => {
    if (!value) return '';
    const parsed = new Date(value);
    if (!Number.isFinite(parsed.getTime())) return '';
    return new Intl.DateTimeFormat('es-CO', {
      timeZone:'America/Bogota', year:'numeric', month:'2-digit', day:'2-digit',
      hour:'2-digit', minute:'2-digit'
    }).format(parsed);
  };

  function hundreds(value) {
    const simple = ['CERO','UNO','DOS','TRES','CUATRO','CINCO','SEIS','SIETE','OCHO','NUEVE','DIEZ',
      'ONCE','DOCE','TRECE','CATORCE','QUINCE','DIECISÉIS','DIECISIETE','DIECIOCHO','DIECINUEVE',
      'VEINTE','VEINTIUNO','VEINTIDÓS','VEINTITRÉS','VEINTICUATRO','VEINTICINCO','VEINTISÉIS',
      'VEINTISIETE','VEINTIOCHO','VEINTINUEVE'];
    if (value < 30) return simple[value];
    if (value < 100) {
      const tens = ['','','','TREINTA','CUARENTA','CINCUENTA','SESENTA','SETENTA','OCHENTA','NOVENTA'];
      return tens[Math.floor(value / 10)] + (value % 10 ? ' Y ' + simple[value % 10] : '');
    }
    if (value === 100) return 'CIEN';
    const names = ['','CIENTO','DOSCIENTOS','TRESCIENTOS','CUATROCIENTOS','QUINIENTOS','SEISCIENTOS','SETECIENTOS','OCHOCIENTOS','NOVECIENTOS'];
    return names[Math.floor(value / 100)] + (value % 100 ? ' ' + hundreds(value % 100) : '');
  }
  const beforeNoun = text => text.replace(/VEINTIUNO$/, 'VEINTIÚN').replace(/UNO$/, 'UN');
  function integerWords(value) {
    if (value < 1000) return hundreds(value);
    if (value < 1000000) {
      const thousands = Math.floor(value / 1000);
      return (thousands === 1 ? 'MIL' : beforeNoun(hundreds(thousands)) + ' MIL')
        + (value % 1000 ? ' ' + hundreds(value % 1000) : '');
    }
    const millions = Math.floor(value / 1000000);
    return (millions === 1 ? 'UN MILLÓN' : beforeNoun(integerWords(millions)) + ' MILLONES')
      + (value % 1000000 ? ' ' + integerWords(value % 1000000) : '');
  }
  function totalWords(total, currency = 'COP') {
    const cents = Math.round(Number(total) * 100);
    if (!Number.isSafeInteger(cents) || cents < 0 || cents >= 100000000000000) return amount(total) + ' ' + currency;
    const integer = Math.floor(cents / 100);
    const unit = currency === 'COP' ? (integer === 1 ? 'PESO' : 'PESOS') : currency;
    const connector = integer > 0 && integer % 1000000 === 0 && currency === 'COP' ? ' DE ' : ' ';
    return beforeNoun(integerWords(integer)) + connector + unit + ' CON ' + String(cents % 100).padStart(2,'0') + '/100';
  }

  function barcode(reference) {
    const text = String(reference || '').toUpperCase();
    if (!/^[0-9A-Z. $/+%\-]{1,24}$/.test(text)) return '';
    // Símbolos CODE39 de JsBarcode (MIT), src/barcodes/CODE39/index.js.
    // Copyright (c) 2016 Johan Lindell (johan@lindell.me).
    // https://github.com/lindell/JsBarcode
    const characters = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%*';
    const patterns = [20957,29783,23639,30485,20951,29813,23669,20855,29789,23645,
      29975,23831,30533,22295,30149,24005,21623,29981,23837,22301,30023,23879,
      30545,22343,30161,24017,21959,30065,23921,22385,29015,18263,29141,17879,
      29045,18293,17783,29021,18269,17477,17489,17681,20753,35770];
    let encoded = patterns[43].toString(2);
    for (const char of text) encoded += patterns[characters.indexOf(char)].toString(2) + '0';
    encoded += patterns[43].toString(2);
    const stripes = [];
    for (let offset = 0; offset < encoded.length;) {
      const bit = encoded[offset];
      let end = offset + 1;
      while (end < encoded.length && encoded[end] === bit) end++;
      if (bit === '1') stripes.push(`<rect x="${offset + 12}" y="0" width="${end - offset}" height="40"/>`);
      offset = end;
    }
    return `<svg viewBox="0 0 ${encoded.length + 24} 40" role="img" aria-label="Referencia ERP ${escape(text)}" preserveAspectRatio="none">${stripes.join('')}</svg>`;
  }

  function itemPrice(item) {
    const base = Number(item.base) || 0;
    const count = Number(item.cantidad) || 0;
    const pct = item.descuentoPorcentaje == null ? null : Number(item.descuentoPorcentaje);
    let gross = base;
    if (Number(item.precioBaseConIva) > 0 && pct > 0 && pct <= 100) {
      const original = round(Number(item.precioBaseConIva) * count / (1 + Number(item.ivaTarifa || 0) / 100));
      if (original >= base) gross = original;
    }
    return { base, gross, discount:round(gross - base), percent:pct, unit:count ? gross / count : 0 };
  }
  function unitDescription(unit) {
    return [['Chasis',unit.chasis],['Motor',unit.motor],['VIN',unit.vin],['Serial',unit.serial]]
      .filter(([,value]) => value).map(([name,value]) => name + ' ' + value).join(' · ');
  }
  function itemRows(item) {
    const price = itemPrice(item);
    const presentations = [...new Set((item.unidades || []).map(unit => [unit.modelo && 'MOD ' + unit.modelo, unit.color].filter(Boolean).join(' · ')).filter(Boolean))];
    const presentation = presentations.join(', ') || item.unidad || '—';
    const lines = [`<tr class="invoice-item"><td>${escape(item.codigo)}</td><td>${escape(item.descripcion)}</td>
      <td>${escape(presentation)}</td><td>${escape(item.bodegaCodigo || '—')}</td><td>${escape(item.lote || '—')}</td>
      <td class="numeric">${quantity(item.cantidad)}</td><td class="numeric">${amount(price.unit)}</td>
      <td class="numeric">${price.percent == null ? '—' : quantity(price.percent)}</td>
      <td class="numeric">${quantity(item.ivaTarifa)}</td><td class="numeric">${amount(price.gross)}</td></tr>`];
    for (const unit of item.unidades || []) {
      const identity = unitDescription(unit);
      if (identity) lines.push(`<tr class="invoice-unit"><td colspan="10">${escape(identity)}</td></tr>`);
    }
    return lines.join('');
  }

  function html(data, company, options = {}) {
    const h = data.header;
    const issuer = data.empresa || {};
    const issuerName = issuer.razonSocial || company.name;
    const rawNit = String(issuer.nit || company.nit || '').replace(/^NIT\s*/i, '').trim();
    const nit = rawNit + (issuer.digitoVerificacion && !rawNit.includes('-') ? '-' + issuer.digitoVerificacion : '');
    const printed = timestamp(options.printedAt || new Date());
    const bodyConcepts = (data.conceptos || []).filter(item => item.mostrarEnCuerpo ?? item.ubicacionFormato !== 'TOTALES');
    const totalConcepts = (data.conceptos || []).filter(item => item.mostrarEnTotales ?? item.ubicacionFormato === 'TOTALES');
    const prices = data.articulos.map(itemPrice);
    const base = data.articulos.reduce((sum,item) => sum + Number(item.base || 0), 0);
    const vat = data.articulos.reduce((sum,item) => sum + Number(item.iva || 0), 0);
    const gross = prices.reduce((sum,item) => sum + item.gross, 0);
    const discount = prices.reduce((sum,item) => sum + item.discount, 0);
    const conceptsTotal = (data.conceptos || []).reduce((sum,item) => sum + Number(item.valor || 0), 0);
    const taxes = new Map();
    for (const item of data.articulos) {
      const rate = Number(item.ivaTarifa || 0);
      const tax = taxes.get(rate) || { base:0, value:0 };
      tax.base += Number(item.base || 0);
      tax.value += Number(item.iva || 0);
      taxes.set(rate, tax);
    }
    const currency = h.moneda || company.currency || 'COP';
    const rows = data.articulos.map(itemRows).join('') + bodyConcepts.map(item => `<tr class="invoice-concept"><td>${escape(item.codigo)}</td><td colspan="8">${escape(item.nombre)}</td><td class="numeric">${amount(item.valor)}</td></tr>`).join('');
    return `<div class="invoice-paper">
      <header class="invoice-heading">
        <div class="invoice-issuer"><h2>${escape(issuerName)}</h2><p>NIT ${escape(nit)}</p>
          ${issuer.direccion ? `<p>Dirección: ${escape(issuer.direccion)}</p>` : ''}
          ${issuer.telefono ? `<p>Teléfonos: ${escape(issuer.telefono)}</p>` : ''}
          ${issuer.ciudad ? `<p>${escape(issuer.ciudad)}</p>` : ''}
          <h1>FACTURA DE VENTA</h1>
        </div>
        <div class="invoice-print-time"><strong>Fecha de impresión</strong><span>${escape(printed)}</span></div>
      </header>
      <section class="invoice-document">
        <dl><dt>No. Factura</dt><dd>${escape(h.numero)}</dd><dt>No. Interno</dt><dd>${escape(h.id ?? h.numero)}</dd>
          <dt>Fecha</dt><dd>${date(h.fecha)}</dd><dt>Sucursal</dt><dd>${escape([h.sucursalCodigo,h.sucursal].filter(Boolean).join(' · '))}</dd></dl>
        <div class="invoice-document-note">${issuer.leyenda ? `<p>${escape(issuer.leyenda)}</p>` : ''}
          <p class="invoice-status">Representación interna del ERP</p>
          ${h.creadoEnUtc ? `<p>Fecha de creación: ${escape(timestamp(h.creadoEnUtc))}</p>` : ''}
        </div>
      </section>
      <section class="invoice-customer">
        <div><strong>Cliente:</strong><span>${escape(h.cliente)}</span></div><div><strong>${escape(h.tipoIdentificacionCliente || 'Identificación')}:</strong><span>${escape(h.identificacion)}${h.digitoVerificacionCliente ? '-' + escape(h.digitoVerificacionCliente) : ''}</span></div>
        <div><strong>Dirección:</strong><span>${escape(h.direccionCliente || '—')}</span></div><div><strong>Teléfono:</strong><span>${escape(h.telefonoCliente || '—')}</span></div>
        <div><strong>Vendedor:</strong><span>${escape(h.vendedor || '—')}</span></div><div><strong>Ciudad:</strong><span>${escape(h.ciudadCliente || '—')}</span></div>
        <div><strong>Moneda:</strong><span>${escape(currency)}</span></div><div><strong>Modalidad:</strong><span>${escape(h.modalidad || 'Venta')}</span></div>
      </section>
      <section class="invoice-merchandise">
        <table class="invoice-items"><colgroup><col class="item-code"><col class="item-name"><col class="item-presentation"><col class="item-warehouse"><col class="item-lot"><col class="item-count"><col class="item-price"><col class="item-discount"><col class="item-tax"><col class="item-total"></colgroup>
          <thead><tr><th>Código</th><th>Nombre</th><th>Presentación</th><th>Bodega</th><th>Lote</th><th>Cantidad</th><th>Precio</th><th>% Dcto.</th><th>% IVA</th><th>Total bruto</th></tr></thead>
          <tbody>${rows || '<tr><td colspan="10">Sin artículos</td></tr>'}</tbody>
        </table>
        <div class="invoice-tax-area"><section><h3>Resumen del IVA</h3><table class="invoice-tax-table"><thead><tr><th>IVA</th><th>Base</th><th>Valor</th></tr></thead>
          <tbody>${[...taxes].sort(([left],[right]) => left-right).map(([rate,tax]) => `<tr><td>${quantity(rate)} %</td><td class="numeric">${amount(tax.base)}</td><td class="numeric">${amount(tax.value)}</td></tr>`).join('') || '<tr><td colspan="3">Sin IVA</td></tr>'}</tbody></table></section></div>
      </section>
      <div class="invoice-bottom">
        <section class="invoice-settlement">
          <div class="invoice-words"><strong>Son</strong><span>${escape(totalWords(h.total,currency))}</span></div>
          <div class="invoice-barcode">${barcode(h.numero)}<span>${escape(h.numero)}</span></div>
          <div class="invoice-observations"><h3>Observaciones</h3><p>${escape(h.observacion || '')}</p></div>
          <table class="invoice-totals"><tbody>
            <tr><th>Total bruto</th><td>${amount(gross)}</td></tr><tr><th>Total descuento</th><td>${amount(discount)}</td></tr>
            <tr><th>Total venta neta</th><td>${amount(base)}</td></tr><tr><th>Total IVA</th><td>${amount(vat)}</td></tr>
            <tr><th>Otros conceptos</th><td>${amount(conceptsTotal)}</td></tr>
            ${totalConcepts.map(item => `<tr class="invoice-concept-total"><th>${escape(item.nombre)}</th><td>${amount(item.valor)}</td></tr>`).join('')}
            <tr class="invoice-grand-total"><th>Total factura</th><td>${amount(h.total)}</td></tr>
          </tbody></table>
        </section>
        <section class="invoice-signatures"><div><span>${escape(h.elaboradoPor || '')}</span><strong>Elaborado por</strong></div>
          <div><span></span><strong>Firma autorizada</strong></div><div><span></span><strong>Firma y sello del cliente</strong><p>Nombre y C.C. de quien recibe<br>Fecha de recibido:</p></div></section>
        <footer class="invoice-fiscal-status">No válido como factura electrónica DIAN. No contiene resolución de numeración, CUFE, código QR ni validación previa de la DIAN.</footer>
      </div>
    </div>`;
  }

  let printNode = null;
  function print(data, company) {
    if (!data?.header || !company) throw new Error('No hay datos suficientes para imprimir la factura.');
    printNode?.remove();
    const printed = document.createElement('article');
    printed.id = 'salesInvoicePrint';
    printed.innerHTML = html(data,company);
    printNode = printed;
    document.body.append(printed);
    document.body.classList.add('printing-sales-invoice');
    const cleanup = () => {
      window.removeEventListener('afterprint',cleanup);
      printed.remove();
      if (printNode === printed) {
        printNode = null;
        document.body.classList.remove('printing-sales-invoice');
      }
    };
    window.addEventListener('afterprint',cleanup,{once:true});
    try { window.print(); } catch (error) { cleanup(); throw error; }
    window.setTimeout(cleanup,120000);
  }
  window.salesInvoicePrint = { html,print };
})();
