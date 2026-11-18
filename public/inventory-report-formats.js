(() => {
  const column = (label, type, width, total = false) => ({label, type, width, total});
  const text = value => value == null ? '' : String(value);
  function quantity(value) {
    if (value == null || value === '') return '';
    const numeric = typeof value === 'number' ? value : Number(value);
    if (!Number.isFinite(numeric)) throw new Error('La consulta contiene una cantidad inválida.');
    return numeric;
  }
  function date(value) {
    if (value == null || value === '') return '';
    const input = Object.prototype.toString.call(value) === '[object Date]' ? value.toISOString() : String(value);
    if (!/^\d{4}-\d{2}-\d{2}/.test(input)) throw new Error('La consulta contiene una fecha inválida.');
    return input.slice(0, 10);
  }
  function bogotaTimestamp(value) {
    if (value == null || value === '') return '';
    const input = typeof value === 'string' && !/(Z|[+-]\d{2}:\d{2})$/i.test(value) ? value + 'Z' : value;
    const timestamp = new Date(input);
    if (!Number.isFinite(timestamp.getTime())) throw new Error('La consulta contiene una fecha de revisión inválida.');
    return new Intl.DateTimeFormat('es-CO', {
      timeZone:'America/Bogota', year:'numeric', month:'2-digit', day:'2-digit',
      hour:'2-digit', minute:'2-digit', second:'2-digit', hourCycle:'h23'
    }).format(timestamp);
  }
  const warehouse = value => [value?.codigo, value?.nombre].filter(part => part != null && part !== '').map(text).join(' · ');

  function receipts(source, view) {
    return {
      view,
      title:view === 'receiving' ? 'Recepción física de mercancía' : 'Historial de recepciones',
      sheetName:view === 'receiving' ? 'Recepción física' : 'Historial recepciones',
      recordLabel:'recepciones',
      columns:[
        column('Recepción','text',23),column('Estado','text',20),column('Tipo documento','text',18),
        column('Factura proveedor','text',24),column('Proveedor','text',38),column('Bodega','text',26),
        column('Fecha factura','date',16),column('Fecha contable','date',16),
        column('Líneas','quantity',13,true),column('Unidades serializadas','quantity',21,true),
        column('Revisadas','quantity',15,true),column('Recibidas conformes','quantity',21,true),
        column('Recibidas con novedad','quantity',23,true),column('No recibidas','quantity',17,true)
      ],
      rows:source.map(item => [
        text(item.numero),text(item.estado),text(item.tipoDocumento),text(item.numeroDocumento),text(item.proveedor),text(item.bodega),
        date(item.fechaDocumento),date(item.fechaContable),quantity(item.lineas),quantity(item.unidadesSerializadas),
        quantity(item.revisadas),quantity(item.recibidasConforme),quantity(item.recibidasConNovedad),quantity(item.noRecibidas)
      ])
    };
  }

  function issues(source) {
    return {
      view:'receipt-issues',title:'Novedades de recepción',sheetName:'Novedades',recordLabel:'novedades',
      columns:[
        column('Recepción','text',23),column('Tipo documento','text',18),column('Factura proveedor','text',24),
        column('Proveedor','text',38),column('Fecha factura','date',16),column('Fecha contable','date',16),
        column('Bodega','text',26),column('Línea','quantity',11),column('Unidad','quantity',11),
        column('Código artículo','text',22),column('Descripción','text',40),
        column('Serial','text',27),column('Motor','text',27),column('Chasis','text',31),column('VIN','text',31),
        column('Color','text',18),column('Modelo','text',17),column('Novedad','text',24),column('Observación','text',46),
        column('Revisado por','text',29),column('Fecha revisión (Bogotá)','text',29)
      ],
      rows:source.map(item => [
        text(item.recepcionNumero),text(item.tipoDocumento),text(item.numeroDocumento),text(item.proveedor),
        date(item.fechaDocumento),date(item.fechaContable),text(item.bodega),quantity(item.numeroLinea),quantity(item.numeroUnidad),
        text(item.codigoArticulo),text(item.descripcion),text(item.serial),text(item.motor),text(item.chasis),text(item.vin),
        text(item.color),text(item.modelo),text(item.estadoFisico),text(item.observacion),text(item.revisadoPor),bogotaTimestamp(item.revisadoEnUtc)
      ])
    };
  }

  function serials(source) {
    return {
      view:'serials',title:'Unidades serializadas',sheetName:'Seriales',recordLabel:'unidades',
      columns:[
        column('Código artículo','text',22),column('Descripción','text',40),column('Estado','text',21),column('Bodega actual','text',27),
        column('Serial','text',27),column('Motor','text',27),column('Chasis','text',31),column('VIN','text',31),column('Placa','text',17)
      ],
      rows:source.map(item => [
        text(item.codigo),text(item.descripcion),text(item.estado),text(item.bodega),text(item.serial),
        text(item.motor),text(item.chasis),text(item.vin),text(item.placa)
      ])
    };
  }

  function expiry(source) {
    return {
      view:'expiry',title:'Vencimientos de inventario',sheetName:'Vencimientos',recordLabel:'registros',
      columns:[
        column('Bodega','text',26),column('Código artículo','text',22),column('Descripción','text',40),
        column('Lote','text',23),column('Fecha vencimiento','date',19),column('Días para vencer','quantity',19),
        column('Estado','text',21),column('Existencia','quantity',17,true)
      ],
      rows:source.map(item => [
        text(item.bodega),text(item.codigo),text(item.descripcion),text(item.numeroLote),date(item.fechaVencimiento),
        quantity(item.diasParaVencer),text(item.estado),quantity(item.existencia)
      ])
    };
  }

  function transferQuantity(item) {
    if (item.cantidad != null) return quantity(item.cantidad);
    if (!Array.isArray(item.lineas) || !item.lineas.length || item.lineas.some(line => line.cantidad == null || line.cantidad === '')) return '';
    return item.lineas.reduce((sum, line) => sum + quantity(line.cantidad), 0);
  }
  function transfers(source) {
    const hasObservation = source.some(item => Object.hasOwn(item,'observacion'));
    const amounts = source.map(transferQuantity);
    const hasQuantity = amounts.some(value => typeof value === 'number');
    const columns = [
      column('Traslado','text',23),column('Estado','text',21),column('Fecha salida','date',17),column('Fecha contable','date',17),
      column('Bodega origen','text',31),column('Bodega destino','text',31),
      column('Traslado original','text',24),column('Traslado de reversión','text',26)
    ];
    if (hasObservation) columns.push(column('Observación','text',46));
    if (hasQuantity) columns.push(column('Cantidad','quantity',17,true));
    const rows = source.map((item, index) => {
      const values = [
        text(item.numero),text(item.estado),date(item.fechaSalida),date(item.fechaContable),
        warehouse(item.bodegaOrigen),warehouse(item.bodegaDestino),text(item.numeroOriginal),text(item.numeroReversion)
      ];
      if (hasObservation) values.push(text(item.observacion));
      if (hasQuantity) values.push(amounts[index]);
      return values;
    });
    return {view:'transfers',title:'Traslados entre bodegas',sheetName:'Traslados',recordLabel:'traslados',columns,rows};
  }

  function model(source, context) {
    const view = context?.view;
    const records = view === 'transfers' && !Array.isArray(source) ? source?.items : source;
    if (!Array.isArray(records)) throw new Error('No se encontraron datos válidos para el informe de inventario.');
    let format;
    switch (view) {
      case 'receiving':
      case 'receipt-history': format = receipts(records, view); break;
      case 'receipt-issues': format = issues(records); break;
      case 'serials': format = serials(records); break;
      case 'expiry': format = expiry(records); break;
      case 'transfers': format = transfers(records); break;
      default: throw new Error('La consulta de inventario no tiene un formato de informe disponible.');
    }
    const totals = {};
    format.columns.forEach((definition, index) => {
      if (definition.total) {
        totals[index] = Number(format.rows.reduce((sum, row) => sum + (typeof row[index] === 'number' ? row[index] : 0), 0).toFixed(6));
      }
    });
    return {...JSON.parse(JSON.stringify(context)),...format,generatedAt:new Date().toISOString(),totals};
  }

  window.inventoryReportFormats = {model};
})();
