(() => {
  const spreadsheetNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const relationshipNs = 'http://schemas.openxmlformats.org/package/2006/relationships';
  const xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const dayMilliseconds = 86400000;
  const clean = value => String(value ?? '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF\uD800-\uDFFF]/gu, '');
  const escape = value => clean(value).replace(/[&<>"']/g, character => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&apos;'
  })[character]);

  function columnName(index) {
    let name = '';
    for (let number = index + 1; number > 0; number = Math.floor((number - 1) / 26)) {
      name = String.fromCharCode(65 + (number - 1) % 26) + name;
    }
    return name;
  }

  function excelDate(value) {
    const input = Object.prototype.toString.call(value) === '[object Date]'
      ? Number.isFinite(value.getTime()) ? value.toISOString() : ''
      : String(value);
    const parts = /^(\d{4})-(\d{2})-(\d{2})(?:$|T)/.exec(input);
    if (!parts) throw new Error('El informe contiene una fecha inválida.');
    const [year, month, day] = parts.slice(1).map(Number);
    const instant = new Date(Date.UTC(year, month - 1, day));
    if (year < 1900 || year > 9999 || instant.getUTCFullYear() !== year
        || instant.getUTCMonth() !== month - 1 || instant.getUTCDate() !== day) {
      throw new Error('El informe contiene una fecha inválida.');
    }
    const days = (instant.getTime() - Date.UTC(1899, 11, 31)) / dayMilliseconds;
    return days + (instant.getTime() >= Date.UTC(1900, 2, 1) ? 1 : 0);
  }

  function textCell(reference, value, style = 0) {
    const text = clean(value);
    if (text.length > 32767) throw new Error('Un texto del informe excede el límite de una celda de Excel.');
    return `<c r="${reference}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${escape(text)}</t></is></c>`;
  }

  function numberCell(reference, value, style, formula) {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw new Error('El informe contiene una cantidad o un valor inválido.');
    }
    return `<c r="${reference}" s="${style}">${formula ? `<f>${formula}</f>` : ''}<v>${value}</v></c>`;
  }

  function columnWidth(column) {
    if (column.width != null) {
      if (!Number.isFinite(column.width) || column.width <= 0 || column.width > 255) {
        throw new Error('Revisa el ancho de las columnas del informe.');
      }
      return column.width;
    }
    if (column.type === 'date') return 13;
    if (column.type === 'quantity') return 14;
    if (column.type === 'money') return 19;
    if (/chasis|vin|motor|serial/i.test(column.label)) return 31;
    if (/descrip|producto/i.test(column.label)) return 38;
    if (/documento|factura|comprobante|movimiento|estado/i.test(column.label)) return 24;
    return 19;
  }

  function rowHeight(values, widths, minimum = 24) {
    return Math.min(409, Math.max(minimum, ...values.map((value, index) => {
      if (typeof value !== 'string') return 0;
      return value.split(/\r?\n/).reduce((lines, part) => lines + Math.max(1, Math.ceil(part.length / widths[index])), 0) * 14 + 8;
    })));
  }

  function styles() {
    const format = (number, font = 0, fill = 0, border = 0, align = 'left', vertical = 'top') =>
      `<xf numFmtId="${number}" fontId="${font}" fillId="${fill}" borderId="${border}" xfId="0" applyAlignment="1" applyNumberFormat="1"><alignment horizontal="${align}" vertical="${vertical}" wrapText="1"/></xf>`;
    return `${xmlHeader}<styleSheet xmlns="${spreadsheetNs}">
      <numFmts count="3"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="#,##0.######;-#,##0.######;0"/><numFmt numFmtId="166" formatCode="#,##0.00;[Red](#,##0.00);0.00"/></numFmts>
      <fonts count="5">
        <font><sz val="10"/><color rgb="FF223C32"/><name val="Aptos"/></font>
        <font><b/><sz val="16"/><color rgb="FF195540"/><name val="Aptos"/></font>
        <font><b/><sz val="12"/><color rgb="FF195540"/><name val="Aptos"/></font>
        <font><sz val="10"/><color rgb="FF596F64"/><name val="Aptos"/></font>
        <font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font>
      </fonts>
      <fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF195540"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEAF3EE"/><bgColor indexed="64"/></patternFill></fill></fills>
      <borders count="2"><border/><border><top style="thin"><color rgb="FFB8CDBF"/></top></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="11">${format(49)}${format(0,1)}${format(0,2)}${format(0,3)}${format(0,4,2,0,'center','center')}
        ${format(164)}${format(165,0,0,0,'right')}${format(166,0,0,0,'right')}
        ${format(0,2,3,1)}${format(165,2,3,1,'right')}${format(166,2,3,1,'right')}</cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>`;
  }

  function workbook(report) {
    if (!report?.company || !Array.isArray(report.columns) || !report.columns.length
        || report.columns.length > 16384 || !Array.isArray(report.rows)) {
      throw new Error('No se pudo preparar la estructura del informe para Excel.');
    }
    const view = report.view || 'kardex';
    const stock = view === 'stock';
    const aging = view === 'aging';
    const sheetName = report.sheetName || (aging ? 'Edad de artículos' : stock ? 'Existencias' : 'Kardex');
    if (sheetName.length > 31 || /[\\/?*\[\]:]/.test(sheetName)) throw new Error('El nombre de la hoja del informe no es válido.');
    const sheetReference = escape(sheetName.replaceAll("'", "''"));
    const title = report.title?.toLocaleUpperCase('es-CO') || (aging ? 'EDAD DE ARTÍCULOS' : stock ? 'EXISTENCIAS' : 'KARDEX');
    const dated = ['kardex','receipt-history','receipt-issues'].includes(view);
    const columns = report.columns;
    if (report.rows.length > 1048566 || columns.some(column => !['text','date','quantity','money'].includes(column.type)
        || column.total === true && !['quantity','money'].includes(column.type))) {
      throw new Error('Revisa las columnas y la cantidad de registros del informe.');
    }
    const generated = new Date(report.generatedAt || Date.now());
    if (!Number.isFinite(generated.getTime())) throw new Error('La fecha de generación del informe no es válida.');
    const generatedLabel = new Intl.DateTimeFormat('es-CO', {
      timeZone:'America/Bogota', year:'numeric', month:'2-digit', day:'2-digit',
      hour:'2-digit', minute:'2-digit', second:'2-digit', hourCycle:'h23'
    }).format(generated);
    const unit = report.unit;
    const identifiers = unit ? [['Chasis',unit.chasis],['VIN',unit.vin],['Motor',unit.motor],['Serial',unit.serial],['Placa',unit.placa]]
      .filter(([,value]) => value).map(([label,value]) => `${label} ${value}`).join(' · ') : '';
    const context = [
      [report.demo ? title + ' · Datos de demostración' : title, 1],
      [report.company.name, 2],
      [`NIT ${String(report.company.nit ?? '').replace(/^NIT\s*/i, '')}${report.columns.some(col => col.type === 'money') ? ' · Moneda ' + (report.company.currency || 'COP') : ''}`, 3],
      [aging ? 'Edad desde la fecha contable de la entrada original' : stock ? 'Existencias actuales' : dated ? `Desde ${report.from || 'Sin límite'} · Hasta ${report.until || 'Sin límite'}` : report.view === 'expiry' ? 'Vencidos y próximos a vencer en 365 días' : 'Consulta actual', 3],
      [`Bodega ${report.warehouseLabel || 'Todas las bodegas'}`, 3],
      [`Búsqueda ${report.query || 'Sin filtro'}`, 3],
      [aging ? `Antigüedad ${report.ageBandLabel || 'Todas las edades'}` : view === 'receipt-issues' ? `Novedad ${report.issueTypeLabel || 'Todas'}` : view !== 'kardex' ? `Registros ${report.rows.length}` : unit ? `Unidad ${identifiers || unit.unidadSerializadaId || unit.id || ''}` : 'Unidad Todas las unidades', 3],
      [`Generado ${generatedLabel} · Bogotá, Colombia`, 3]
    ];
    const last = columnName(columns.length - 1);
    const widths = columns.map(columnWidth);
    const availableWidth = widths.reduce((sum, width) => sum + width, 0);
    const sheet = context.map(([value, style], index) =>
      `<row r="${index + 1}" ht="${rowHeight([String(value ?? '')], [availableWidth], index ? 20 : 30)}" customHeight="1">${textCell(`A${index + 1}`, value, style)}</row>`);
    const headerRow = 9;
    const firstDataRow = headerRow + 1;
    sheet.push(`<row r="${headerRow}" ht="${rowHeight(columns.map(column => column.label), widths, 30)}" customHeight="1">${columns.map((column, index) => textCell(`${columnName(index)}${headerRow}`, column.label, 4)).join('')}</row>`);
    const sums = columns.map(() => 0);
    report.rows.forEach((values, index) => {
      if (!Array.isArray(values) || values.length !== columns.length) throw new Error('Una fila del informe no coincide con sus columnas.');
      const at = firstDataRow + index;
      const cells = values.map((value, columnIndex) => {
        const column = columns[columnIndex];
        const reference = `${columnName(columnIndex)}${at}`;
        const style = {text:0,date:5,quantity:6,money:7}[column.type];
        if (value == null || value === '') return `<c r="${reference}" s="${style}"/>`;
        if (column.type === 'text') return textCell(reference, value);
        if (column.type === 'date') return numberCell(reference, excelDate(value), style);
        if (column.total === true && typeof value === 'number') sums[columnIndex] += value;
        return numberCell(reference, value, style);
      });
      sheet.push(`<row r="${at}" ht="${rowHeight(values, widths)}" customHeight="1">${cells.join('')}</row>`);
    });
    const dataEnd = headerRow + report.rows.length;
    const hasTotals = columns.some(column => column.total === true);
    const finalRow = hasTotals ? dataEnd + 1 : dataEnd;
    if (hasTotals) {
      const labelIndex = columns.findIndex(column => column.total !== true);
      const totals = columns.map((column, index) => {
        const reference = `${columnName(index)}${finalRow}`;
        if (column.total !== true) return textCell(reference, index === labelIndex ? 'TOTAL' : '', 8);
        const cached = report.totals?.[index] ?? sums[index];
        const formula = report.rows.length ? `SUM(${columnName(index)}${firstDataRow}:${columnName(index)}${dataEnd})` : null;
        return numberCell(reference, cached, column.type === 'money' ? 10 : 9, formula);
      });
      sheet.push(`<row r="${finalRow}" ht="26" customHeight="1">${totals.join('')}</row>`);
    }
    const mergeCells = columns.length > 1
      ? `<mergeCells count="8">${context.map((_, index) => `<mergeCell ref="A${index + 1}:${last}${index + 1}"/>`).join('')}</mergeCells>` : '';
    const files = {
      '[Content_Types].xml':`${xmlHeader}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>`,
      '_rels/.rels':`${xmlHeader}<Relationships xmlns="${relationshipNs}"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>`,
      'docProps/core.xml':`${xmlHeader}<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${escape(sheetName)}</dc:title><dc:creator>Nexo ERP</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">${generated.toISOString()}</dcterms:created></cp:coreProperties>`,
      'xl/workbook.xml':`${xmlHeader}<workbook xmlns="${spreadsheetNs}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets><sheet name="${escape(sheetName)}" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm.Print_Titles" localSheetId="0">'${sheetReference}'!$1:$9</definedName><definedName name="_xlnm.Print_Area" localSheetId="0">'${sheetReference}'!$A$1:$${last}$${finalRow}</definedName></definedNames><calcPr calcId="191029" calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/></workbook>`,
      'xl/_rels/workbook.xml.rels':`${xmlHeader}<Relationships xmlns="${relationshipNs}"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`,
      'xl/styles.xml':styles(),
      'xl/worksheets/sheet1.xml':`${xmlHeader}<worksheet xmlns="${spreadsheetNs}"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:${last}${finalRow}"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="9" topLeftCell="A10" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A10" sqref="A10"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="24"/><cols>${columns.map((_, index) => `<col min="${index + 1}" max="${index + 1}" width="${widths[index]}" customWidth="1"/>`).join('')}</cols><sheetData>${sheet.join('')}</sheetData><autoFilter ref="A9:${last}${dataEnd}"/>${mergeCells}<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.15" footer="0.15"/><pageSetup paperSize="1" orientation="landscape" fitToWidth="1" fitToHeight="0"/><headerFooter><oddFooter>&amp;L Nexo ERP&amp;R Página &amp;P de &amp;N</oddFooter></headerFooter></worksheet>`
    };
    return paymentReportZip(files);
  }

  window.kardexExcel = {workbook};
})();
