(() => {
  const reversePermission = 'INVENTARIO.AJUSTE.REVERSAR';
  const quantity = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 6 });
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  })[char]);
  const warehouse = value => [value?.codigo, value?.nombre].filter(Boolean).join(' · ') || '—';
  const displayDate = value => {
    const parts = String(value ?? '').slice(0, 10).split('-');
    return parts.length === 3 ? parts.reverse().join('/') : '—';
  };
  const accountingDate = transfer => transfer.fechaContable || transfer.fechaSalida;
  const status = transfer => transfer.trasladoReversionId ? 'Revertido' : ({
    RECIBIDO:'Completado', REVERTIDO:'Revertido', BORRADOR:'Borrador', DESPACHADO:'Despachado',
    RECIBIDO_PARCIAL:'Recibido parcialmente', EN_TRANSITO:'En tránsito', CANCELADO:'Cancelado'
  })[transfer.estado] || transfer.estado;
  const unitIdentifiers = unit => [['Serial', unit.serial], ['Chasis', unit.chasis], ['VIN', unit.vin], ['Motor', unit.motor]]
    .filter(([,value]) => value).map(([label,value]) => `${label} ${value}`).join(' · ');
  const canPrint = transfer => ['RECIBIDO', 'REVERTIDO'].includes(transfer.estado);
  const canReverse = transfer => hasPermission(reversePermission) && transfer.estado === 'RECIBIDO'
    && !transfer.trasladoOriginalId && !transfer.trasladoReversionId;
  const endpoint = (company, id) => `/api/v1/companies/${company}/transfers${id ? `/${id}` : ''}`;
  const companyIsActive = company => company === state.erpSession?.company?.id;
  const transferredGoods = lines => lines.map(line => {
    const units = (line.unidades || []).map(unitIdentifiers);
    const parts = [];
    for (let index = 0; index < units.length; index += 4) parts.push(units.slice(index, index + 4));
    if (!parts.length) parts.push([]);
    return parts.map((identifiers, index) => `<tr><td><strong>${escape(line.codigo)}</strong></td>
      <td>${escape(line.descripcion)}</td><td class="transfer-quantity">${index ? '—' : quantity.format(line.cantidad)}</td>
      <td>${identifiers.length ? identifiers.map(value => `<span class="transfer-unit-text">${escape(value || '—')}</span>`).join('') : '—'}</td></tr>`).join('');
  }).join('');
  const goodsTable = lines => `<table class="transfer-goods"><thead><tr><th scope="col">Código</th><th scope="col">Producto</th><th scope="col">Cantidad</th><th scope="col">Seriales e identificadores</th></tr></thead><tbody>${transferredGoods(lines)}</tbody></table>`;
  const route = (origin, destination) => `<div class="transfer-route"><div><span>Origen</span><strong>${escape(warehouse(origin))}</strong></div><b aria-hidden="true">→</b><div><span>Destino</span><strong>${escape(warehouse(destination))}</strong></div></div>`;
  const note = transfer => `<section class="transfer-note"><h3>${transfer.trasladoOriginalId ? 'Motivo de reversión' : 'Observaciones'}</h3><p>${escape(transfer.observacion || 'Sin observaciones')}</p></section>`;

  function receiptHtml(transfer) {
    const company = transfer.empresa || {};
    const nit = [company.nit, company.digitoVerificacion].filter(value => value != null && String(value) !== '').join('-');
    const related = transfer.trasladoOriginalId
      ? `Revierte el traslado ${transfer.numeroOriginal || ''}`
      : transfer.trasladoReversionId ? `Revertido por ${transfer.numeroReversion || ''}` : '';
    return `<header class="transfer-slip-head">
      <div><span class="transfer-slip-kicker">Inventario</span><h1>${transfer.trasladoOriginalId ? 'Reversión de traslado' : 'Comprobante de traslado'}</h1><span class="transfer-slip-company">${escape(company.razonSocial)}${nit ? ` · NIT ${escape(nit)}` : ''}</span></div>
      <div class="transfer-slip-reference"><span>Comprobante</span><strong>${escape(transfer.numero)}</strong><div>${displayDate(accountingDate(transfer))} · ${escape(status(transfer))}</div></div>
    </header>
    ${route(transfer.bodegaOrigen, transfer.bodegaDestino)}
    ${related ? `<p class="transfer-related">${escape(related)}</p>` : ''}
    ${goodsTable(transfer.lineas || [])}
    ${note(transfer)}`;
  }

  let printNode;
  function print(transfer) {
    if (!canPrint(transfer) || !transfer.lineas?.length) throw new Error('El traslado aún no tiene un comprobante para imprimir.');
    printNode?.remove();
    const paper = document.createElement('article');
    paper.id = 'transferPrint';
    paper.innerHTML = receiptHtml(transfer);
    printNode = paper;
    document.body.append(paper);
    document.body.classList.add('printing-transfer');
    const cleanup = () => {
      window.removeEventListener('afterprint', cleanup);
      paper.remove();
      if (printNode === paper) {
        printNode = null;
        document.body.classList.remove('printing-transfer');
      }
    };
    window.addEventListener('afterprint', cleanup, {once:true});
    try { window.print(); } catch (error) { cleanup(); throw error; }
    window.setTimeout(cleanup, 120000);
  }

  function button(text, style = 'secondary') {
    const control = document.createElement('button');
    control.type = 'button';
    control.className = `button ${style}`;
    control.textContent = text;
    return control;
  }

  function attachHistory(container, company, onReversed) {
    const open = button('Traslados guardados');
    open.addEventListener('click', () => openHistory(company, onReversed));
    container.append(open);
  }

  function appendActions(container, company, transferId, onReversed) {
    const actions = document.createElement('div');
    actions.className = 'transfer-document-actions';
    const printButton = button('Imprimir comprobante');
    const open = button('Ver traslado');
    const notice = document.createElement('span');
    notice.setAttribute('role', 'status');
    open.addEventListener('click', () => openHistory(company, onReversed, transferId));
    printButton.addEventListener('click', async () => {
      printButton.disabled = true;
      notice.textContent = '';
      try {
        const transfer = await apiRequest(endpoint(company, transferId), {cache:'no-store'});
        if (companyIsActive(company) && actions.isConnected) print(transfer);
      } catch (error) {
        notice.textContent = error.status === 404 ? 'Actualiza el backend para consultar el comprobante.' : error.message;
      } finally {
        printButton.disabled = false;
      }
    });
    actions.append(printButton, open, notice);
    container.append(actions);
  }

  function openHistory(company, onReversed, initialId) {
    if (!companyIsActive(company)) return;
    const dialog = document.createElement('dialog');
    dialog.className = 'erp-dialog transfer-documents';
    dialog.setAttribute('aria-labelledby', 'transferDocumentsTitle');
    dialog.innerHTML = `<header class="dialog-heading"><h2 id="transferDocumentsTitle">Traslados guardados</h2>
      <button class="dialog-close" data-transfer-close type="button" aria-label="Cerrar">×</button></header>
      <div class="transfer-dialog-body" data-transfer-list>
        <div class="transfer-toolbar"><label>Buscar traslado<input type="search" maxlength="120" placeholder="Número, bodega, producto o serial" data-transfer-query></label>
          <p role="status" data-transfer-list-status></p></div>
        <div class="transfer-list-scroll"><table class="transfer-history-table">
          <thead><tr><th scope="col">Documento</th><th scope="col">Fecha</th><th scope="col">Origen</th><th scope="col">Destino</th><th scope="col">Estado</th><th scope="col">Acción</th></tr></thead>
          <tbody data-transfer-rows></tbody>
        </table></div>
        <div class="transfer-dialog-pager"><button class="button secondary" data-transfer-prev type="button">Anterior</button><span data-transfer-page></span><button class="button secondary" data-transfer-next type="button">Siguiente</button></div>
      </div>
      <div class="transfer-dialog-body" data-transfer-detail hidden>
        <button class="button secondary" data-transfer-back type="button">← Traslados guardados</button>
        <p role="status" class="transfer-dialog-notice" data-transfer-notice hidden></p>
        <div class="transfer-detail-content" data-transfer-content></div>
      </div>`;
    const select = name => dialog.querySelector(`[data-transfer-${name}]`);
    const title = dialog.querySelector('#transferDocumentsTitle');
    const close = select('close'), search = select('query'), rows = select('rows');
    const list = select('list'), detail = select('detail'), content = select('content'), back = select('back');
    const prev = select('prev'), next = select('next'), pageLabel = select('page'), listStatus = select('list-status');
    const notice = select('notice');
    const pageSize = 12;
    let page = 1;
    let listVersion = 0, detailVersion = 0, searchTimer;
    let posting = false;
    const current = () => dialog.open && companyIsActive(company);
    const message = (value, error = false) => {
      notice.textContent = value;
      notice.hidden = !value;
      notice.classList.toggle('transfer-dialog-error', error);
    };

    async function loadList(requestedPage = 1) {
      const version = ++listVersion;
      const params = new URLSearchParams({page:requestedPage, pageSize, q:search.value.trim()});
      prev.disabled = next.disabled = true;
      listStatus.textContent = 'Consultando…';
      try {
        const result = await apiRequest(`${endpoint(company)}?${params}`, {cache:'no-store'});
        if (!current() || version !== listVersion) return;
        page = result.page;
        rows.innerHTML = result.items.map(transfer => `<tr>
          <td><strong>${escape(transfer.numero)}</strong>${transfer.trasladoOriginalId ? `<small>Reversión de ${escape(transfer.numeroOriginal)}</small>` : ''}</td>
          <td>${displayDate(accountingDate(transfer))}</td><td>${escape(warehouse(transfer.bodegaOrigen))}</td><td>${escape(warehouse(transfer.bodegaDestino))}</td>
          <td><span class="transfer-status">${escape(status(transfer))}</span></td>
          <td><button class="button secondary" type="button" data-transfer-id="${Number(transfer.trasladoId)}" aria-label="Ver traslado ${escape(transfer.numero)}">Ver</button></td>
          </tr>`).join('') || '<tr><td class="empty" colspan="6">No se encontraron traslados.</td></tr>';
        const pages = Math.max(1, Math.ceil(result.total / result.pageSize));
        pageLabel.textContent = `Página ${page} de ${pages}`;
        listStatus.textContent = `${result.total} ${result.total === 1 ? 'traslado' : 'traslados'}`;
        prev.disabled = page <= 1;
        next.disabled = page >= pages;
      } catch (error) {
        if (current() && version === listVersion) {
          listStatus.textContent = error.status === 404 ? 'Actualiza el backend para consultar los traslados guardados.' : error.message;
        }
      }
    }

    async function openDocument(id, success = '') {
      const version = ++detailVersion;
      list.hidden = true;
      detail.hidden = false;
      title.textContent = 'Traslado entre bodegas';
      content.replaceChildren();
      message(success || 'Consultando el traslado…');
      back.focus();
      try {
        const transfer = await apiRequest(endpoint(company, id), {cache:'no-store'});
        if (!current() || version !== detailVersion) return;
        title.textContent = `${transfer.trasladoOriginalId ? 'Reversión' : 'Traslado'} ${transfer.numero}`;
        message(success);
        renderDetail(transfer);
      } catch (error) {
        if (!current() || version !== detailVersion) return;
        message([success, error.message].filter(Boolean).join(' '), true);
        const retry = button('Volver a consultar');
        retry.addEventListener('click', () => void openDocument(id, success));
        content.append(retry);
      }
    }

    function renderDetail(transfer) {
      content.innerHTML = `<div class="transfer-detail-meta">
        <div><span class="transfer-status">${escape(status(transfer))}</span><span>${displayDate(accountingDate(transfer))}</span></div>
        <div class="transfer-document-actions" data-transfer-actions></div>
      </div>
      ${route(transfer.bodegaOrigen, transfer.bodegaDestino)}
      <div class="transfer-detail-table">${goodsTable(transfer.lineas || [])}</div>
      ${note(transfer)}`;
      const actions = content.querySelector('[data-transfer-actions]');
      if (canPrint(transfer)) {
        const printButton = button('Imprimir comprobante');
        printButton.addEventListener('click', () => {
          try { print(transfer); } catch (error) { message(error.message, true); }
        });
        actions.append(printButton);
      }
      const relatedId = transfer.trasladoOriginalId || transfer.trasladoReversionId;
      if (relatedId) {
        const related = button(transfer.trasladoOriginalId ? `Ver original ${transfer.numeroOriginal || ''}` : `Ver reversión ${transfer.numeroReversion || ''}`);
        related.addEventListener('click', () => void openDocument(relatedId));
        actions.append(related);
      }
      if (canReverse(transfer)) {
        const reverse = button('Revertir traslado');
        reverse.addEventListener('click', () => showReverseForm(transfer, reverse));
        actions.append(reverse);
      }
    }

    function showReverseForm(transfer, trigger) {
      const form = document.createElement('form');
      form.className = 'transfer-reverse-form';
      form.innerHTML = `<h3>Confirmar reversión</h3>${route(transfer.bodegaDestino, transfer.bodegaOrigen)}
        <div class="transfer-reverse-fields"><label>Fecha contable<input name="date" type="date" required><small data-reverse-period></small></label>
        <label>Motivo de la reversión<textarea name="reason" rows="2" minlength="10" maxlength="500" required></textarea></label></div>
        <p role="alert" class="transfer-dialog-notice transfer-dialog-error" hidden></p>
        <div class="transfer-document-actions"><button type="button" class="button secondary">Cancelar</button><button type="submit" class="button primary">Confirmar reversión</button></div>`;
      trigger.disabled = true;
      back.disabled = true;
      content.append(form);
      const {date, reason} = form.elements;
      const periodLabel = form.querySelector('[data-reverse-period]');
      const errorText = form.querySelector('[role="alert"]');
      const cancel = form.querySelector('[type="button"]');
      const submit = form.querySelector('[type="submit"]');
      const originalDate = String(accountingDate(transfer) || '').slice(0, 10);
      date.min = originalDate;
      date.value = [accountingToday(), originalDate].sort().at(-1);
      function updatePeriod() {
        const period = receiptPeriodForDate(date.value);
        periodLabel.textContent = period ? `Período ${period.codigo}` : 'La fecha debe estar en un período abierto.';
        submit.disabled = posting || !period;
        return period;
      }
      date.addEventListener('change', updatePeriod);
      cancel.addEventListener('click', () => {
        form.remove();
        trigger.disabled = back.disabled = false;
        trigger.focus();
      });
      form.addEventListener('submit', async event => {
        event.preventDefault();
        if (posting || !current()) return;
        const period = updatePeriod();
        const motive = reason.value.trim();
        if (!period || motive.length < 10) {
          errorText.textContent = 'Escribe un motivo de al menos 10 caracteres y selecciona una fecha contable válida.';
          errorText.hidden = false;
          return;
        }
        posting = true;
        date.disabled = reason.disabled = cancel.disabled = close.disabled = submit.disabled = true;
        submit.textContent = 'Revirtiendo…';
        errorText.hidden = true;
        try {
          const result = await apiRequest(`${endpoint(company, transfer.trasladoId)}/reverse`, {
            method:'POST',
            body:JSON.stringify({periodoInventarioId:period.periodoInventarioId, fechaContable:date.value, motivo:motive})
          });
          if (!current()) return;
          onReversed?.(transfer.trasladoId);
          const confirmation = ['Traslado revertido. Mercancía devuelta a la bodega de origen.', result.zeus?.mensaje].filter(Boolean).join(' ');
          back.disabled = false;
          void openDocument(result.documentoId, confirmation);
        } catch (error) {
          errorText.textContent = error.message;
          errorText.hidden = false;
        } finally {
          posting = false;
          date.disabled = reason.disabled = cancel.disabled = close.disabled = false;
          submit.textContent = 'Confirmar reversión';
          updatePeriod();
        }
      });
      updatePeriod();
      reason.focus();
    }

    close.addEventListener('click', () => dialog.close());
    search.addEventListener('input', () => {
      clearTimeout(searchTimer);
      listVersion++;
      searchTimer = setTimeout(() => void loadList(), 220);
    });
    rows.addEventListener('click', event => {
      const choice = event.target.closest('[data-transfer-id]');
      if (choice) void openDocument(Number(choice.dataset.transferId));
    });
    prev.addEventListener('click', () => void loadList(page - 1));
    next.addEventListener('click', () => void loadList(page + 1));
    back.addEventListener('click', () => {
      detailVersion++;
      detail.hidden = true;
      list.hidden = false;
      title.textContent = 'Traslados guardados';
      search.focus();
      void loadList(page);
    });
    dialog.addEventListener('cancel', event => { if (posting) event.preventDefault(); });
    dialog.addEventListener('close', () => {
      clearTimeout(searchTimer);
      dialog.remove();
    }, {once:true});
    document.body.append(dialog);
    dialog.showModal();
    if (initialId) void openDocument(initialId);
    else {
      search.focus();
      void loadList();
    }
  }

  window.transferDocuments = { attachHistory, appendActions, receiptHtml, print };
})();
