import { SpreadsheetFile, Workbook } from '@oai/artifact-tool';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

const COLORS = { green: '#1F5846', pale: '#DBE9DF', orange: '#D8713B', ink: '#17211D', line: '#D9D6CC', white: '#FFFFFF' };

function cleanSheetName(name, used) {
  const base = String(name || 'Detalle').replace(/[\\/*?:[\]]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 31) || 'Detalle';
  let candidate = base;
  let index = 2;
  while (used.has(candidate.toLowerCase())) {
    const suffix = ` ${index++}`;
    candidate = `${base.slice(0, 31 - suffix.length)}${suffix}`;
  }
  used.add(candidate.toLowerCase());
  return candidate;
}

function typedValue(value, key = '') {
  if (value === null || value === undefined || value === '') return null;
  if (/(^|[.@/])id(entificacion)?$/i.test(key) || /codigo|numero/i.test(key)) return String(value);
  if (typeof value === 'string' && /^-?\d+(?:\.\d+)?$/.test(value)) {
    const number = Number(value);
    if (Number.isSafeInteger(number) || value.includes('.')) return number;
  }
  return value;
}

function styleDataSheet(sheet, matrix) {
  const rowCount = matrix.length;
  const columnCount = matrix[0].length;
  sheet.showGridLines = false;
  sheet.freezePanes.freezeRows(1);
  const header = sheet.getRangeByIndexes(0, 0, 1, columnCount);
  header.format = {
    fill: COLORS.green,
    font: { bold: true, color: COLORS.white },
    rowHeight: 25,
    verticalAlignment: 'center',
  };
  if (rowCount > 1) {
    const data = sheet.getRangeByIndexes(1, 0, rowCount - 1, columnCount);
    data.format.borders = { insideHorizontal: { style: 'thin', color: COLORS.line } };
    data.format.rowHeight = 20;
  }
  for (let column = 0; column < columnCount; column += 1) {
    const range = sheet.getRangeByIndexes(0, column, Math.max(rowCount, 1), 1);
    const longest = matrix.reduce((max, row) => Math.max(max, String(row[column] ?? '').length), 0);
    range.format.columnWidth = Math.min(Math.max(longest + 2, 11), 46);
  }
}

function addMatrixSheet(workbook, name, headers, rows, usedNames) {
  const sheet = workbook.worksheets.add(cleanSheetName(name, usedNames));
  const matrix = [headers, ...rows];
  sheet.getRangeByIndexes(0, 0, matrix.length, headers.length).values = matrix;
  styleDataSheet(sheet, matrix);
  return sheet;
}

export async function buildExcelWorkbook(payload) {
  const workbook = Workbook.create();
  const usedNames = new Set();
  const summary = workbook.worksheets.add(cleanSheetName('Resumen', usedNames));
  summary.showGridLines = false;
  summary.getRange('A1:D1').merge();
  summary.getRange('A1').values = [[`Atlas XML · ${payload.documentTitle || 'Documento XML'}`]];
  summary.getRange('A1:D1').format = { fill: COLORS.green, font: { bold: true, color: COLORS.white, size: 16 }, rowHeight: 34, verticalAlignment: 'center' };
  summary.getRange('A3:B7').values = [
    ['Indicador', 'Valor'],
    ['Campos de cabecera', payload.headers.length],
    ['Grupos de detalle', payload.details.length],
    ['Registros de detalle', payload.details.reduce((sum, group) => sum + group.rows.length, 0)],
    ['Total de campos', payload.fields.length],
  ];
  summary.getRange('A3:B3').format = { fill: COLORS.orange, font: { bold: true, color: COLORS.white } };
  summary.getRange('A4:A7').format.font = { bold: true, color: COLORS.ink };
  summary.getRange('B4:B7').format.numberFormat = '#,##0';
  summary.getRange('A3:B7').format.borders = { insideHorizontal: { style: 'thin', color: COLORS.line }, outside: { style: 'thin', color: COLORS.line } };
  summary.getRange('A:A').format.columnWidth = 25;
  summary.getRange('B:B').format.columnWidth = 16;
  summary.getRange('C:D').format.columnWidth = 18;

  if (payload.invoice) {
    const invoice = payload.invoice;
    addMatrixSheet(workbook, 'Factura', ['Campo', 'Valor'], [
      ['Tipo de documento', invoice.documentType],
      ['Número de factura', invoice.number],
      ['Proveedor', invoice.supplier.name],
      ['NIT proveedor', invoice.supplier.identification],
      ['Cliente', invoice.customer.name],
      ['NIT cliente', invoice.customer.identification],
      ['Fecha de emisión', invoice.issueDate],
      ['Fecha de vencimiento', invoice.dueDate],
      ['Moneda', invoice.currency],
      ['Subtotal bruto', invoice.totals.grossSubtotal],
      ['Descuentos de detalle', invoice.totals.allowances],
      ['Subtotal neto', invoice.totals.cost],
      ['Valor antes de impuestos', invoice.totals.taxExclusive],
      ['Valor con impuestos', invoice.totals.taxInclusive],
      ['Otros cargos', invoice.totals.otherCharges],
      ['Fletes detectados', invoice.totals.freight],
      ['Total a pagar', invoice.totals.payable],
    ], usedNames);

    if (invoice.items.length) {
      const itemSheet = addMatrixSheet(workbook, 'Articulos', ['Línea', 'Código', 'Descripción', 'Motor', 'Chasis / VIN', 'Cantidad', 'Unidad', 'Precio unitario', 'Subtotal bruto', 'Descuento', 'Descuento %', 'Impuesto', 'Total neto'], invoice.items.map((item) => [item.line, item.code, item.description, item.motor || '', item.chassis || '', item.quantity, item.unit, item.unitPrice, item.grossTotal, item.discount, item.discountRate, item.tax, item.lineTotal]), usedNames);
      itemSheet.getRangeByIndexes(1, 7, invoice.items.length, 3).format.numberFormat = '#,##0.00';
      itemSheet.getRangeByIndexes(1, 10, invoice.items.length, 1).format.numberFormat = '0.00';
      itemSheet.getRangeByIndexes(1, 11, invoice.items.length, 2).format.numberFormat = '#,##0.00';
    }
    if (invoice.taxes.length) {
      const taxSheet = addMatrixSheet(workbook, 'Impuestos', ['Impuesto', 'Tarifa %', 'Base', 'Valor'], invoice.taxes.map((tax) => [tax.name, tax.rate, tax.taxableAmount, tax.amount]), usedNames);
      taxSheet.getRangeByIndexes(1, 1, invoice.taxes.length, 1).format.numberFormat = '0.00';
      taxSheet.getRangeByIndexes(1, 2, invoice.taxes.length, 2).format.numberFormat = '#,##0.00';
    }
    if (invoice.charges.length) {
      const chargeSheet = addMatrixSheet(workbook, 'Fletes y cargos', ['Concepto', 'Base', 'Valor', 'Clasificación'], invoice.charges.map((charge) => [charge.reason, charge.baseAmount, charge.amount, charge.isFreight ? 'Flete' : 'Otro cargo']), usedNames);
      chargeSheet.getRangeByIndexes(1, 1, invoice.charges.length, 2).format.numberFormat = '#,##0.00';
    }
  }

  addMatrixSheet(workbook, 'Cabecera', ['Ruta', 'Valor', 'Tipo'], payload.headers.map((field) => [field.path, typedValue(field.value, field.path), field.type]), usedNames);

  payload.details.forEach((group, index) => {
    const columns = [...new Set(group.rows.flatMap((row) => Object.keys(row)))];
    const rows = group.rows.map((row) => columns.map((column) => typedValue(row[column], column)));
    addMatrixSheet(workbook, `${index + 1} ${group.name}`, columns, rows, usedNames);
  });

  addMatrixSheet(workbook, 'Todos los datos', ['Sección', 'Ruta', 'Valor', 'Tipo'], payload.fields.map((field) => [field.repeated ? 'Detalle' : 'Cabecera', field.path, typedValue(field.value, field.path), field.type]), usedNames);
  return workbook;
}

export async function exportExcelBuffer(payload) {
  const workbook = await buildExcelWorkbook(payload);
  const output = await SpreadsheetFile.exportXlsx(workbook);
  const temporaryPath = path.join(os.tmpdir(), `atlas-xml-${randomUUID()}.xlsx`);
  try {
    await output.save(temporaryPath);
    return await fs.readFile(temporaryPath);
  } finally {
    await fs.unlink(temporaryPath).catch(() => {});
  }
}
