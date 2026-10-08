using NexoERP.Api.Treasury;

static void Check(bool ok,string name)
{
    if(!ok)throw new Exception(name);
    Console.WriteLine("OK: "+name);
}

var colombian=DisbursementDocumentParser.Parse("""
    MOTOREPUESTOS SAS
    NIT: 900.749.690-0
    FACTURA ELECTRÓNICA DE VENTA No. FE12345
    Fecha de emisión: 2026-10-08
    SUBTOTAL: $ 34.750.797
    IVA: $ 6.602.651,43
    RETENCIÓN: $ 868.769,93
    TOTAL A PAGAR: $ 40.484.678,50
    ""","Texto del PDF");
Check(colombian.IdentificacionSugerida=="9007496900","NIT normalizado");
Check(colombian.FacturaSugerida=="FE12345","Factura electrónica con prefijo");
Check(colombian.FechaSugerida=="2026-10-08","Fecha del soporte");
Check(colombian.Importes.Any(x=>x.Concepto=="Subtotal"&&x.Valor==34750797m),"Subtotal colombiano");
Check(colombian.Importes.Any(x=>x.Concepto=="Impuestos / IVA"&&x.Valor==6602651.43m),"IVA con decimales");
Check(colombian.Importes.Any(x=>x.Concepto=="Retenciones"&&x.Valor==868769.93m),"Retención separada");
Check(colombian.TotalSugeridoNumero==40484678.50m,"Total a pagar, no subtotal ni IVA");

var foreign=DisbursementDocumentParser.Parse("Invoice ABC-123\nSubtotal USD 1,234.56\nTax: USD 234.56\nTotal: USD 1,469.12","Texto del PDF");
Check(foreign.Importes.Any(x=>x.Concepto=="Subtotal"&&x.Valor==1234.56m),"Separadores internacionales");
Check(foreign.TotalSugeridoNumero==1469.12m,"Total internacional");

var taxRate=DisbursementDocumentParser.Parse("IVA 19%: $ 190.000\nValor pagado: COP 1.190.000","OCR local");
Check(taxRate.Importes.Any(x=>x.Concepto=="Impuestos / IVA"&&x.Valor==190000m),"No confunde tarifa de IVA con valor");
Check(taxRate.TotalSugeridoNumero==1190000m,"Valor pagado de soporte bancario");

var ambiguous=DisbursementDocumentParser.Parse("Total: $ 100.000\nTotal: $ 200.000","Texto del PDF");
Check(ambiguous.TotalSugeridoNumero is null,"Totales incompatibles exigen elección humana");
Check(ambiguous.Importes.Count==2,"Conserva ambos importes para revisión");

var longText=new string('X',13000)+"\nTOTAL A PAGAR: $ 1.234.567,89";
var lastPage=DisbursementDocumentParser.Parse(longText,"Texto del PDF");
Check(lastPage.TotalSugeridoNumero==1234567.89m,"Analiza el total posterior a 12 mil caracteres");
Check(lastPage.Texto.Length<12010&&lastPage.Texto.Contains("1.234.567,89"),"Vista previa incluye final del documento");

var noAmount=DisbursementDocumentParser.Parse("Factura F123\nFecha: 2026-10-08\nReferencia 12345678","Texto del PDF");
Check(noAmount.TotalSugeridoNumero is null&&noAmount.Importes.Count==0,"No convierte factura o fecha en importe");

var unlabelled=DisbursementDocumentParser.Parse("Referencia 12345\nSubtotal $ 100.000\nComisión bancaria $ 4.500\nTOTAL A PAGAR $ 104.500","OCR local");
Check(unlabelled.Importes.Any(x=>x.Concepto=="Otro importe del soporte"&&x.Valor==4500m),"Muestra valores monetarios sin rótulo conocido");
Check(unlabelled.TotalSugeridoNumero==104500m,"Un importe adicional no altera el total elegido");
