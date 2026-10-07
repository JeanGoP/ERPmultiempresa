using NexoERP.Api.Sales;
using NexoERP.Api.Zeus;
using System.Xml.Linq;

static void Check(bool condition,string description)
{
    if(!condition)throw new Exception(description);
    Console.WriteLine("OK: "+description);
}

var monthly=SalesInstallments.Build(new DateOnly(2026,10,3),12,SalesInstallments.SameDayMonthly,1200m);
Check(monthly.Length==12&&monthly[0].Vencimiento==new DateOnly(2026,10,3)
    &&monthly[1].Vencimiento==new DateOnly(2026,11,3)
    &&monthly[11].Vencimiento==new DateOnly(2027,9,3),"doce cuotas al mismo día de cada mes");
Check(monthly.All(x=>x.Valor==100m)&&monthly.Sum(x=>x.Valor)==1200m,"doce saldos exactos en cartera");
var invoiceDate=new DateTime(2026,9,30);
var settings=new ZeusSettings(true,"Zeus","Pruebas","12","00","Local","zeussql","FA",[],[]);
var source=new ZeusSource(0,1,"FV-1",invoiceDate,invoiceDate,monthly[0].Vencimiento.ToDateTime(TimeOnly.MinValue),1200m,0,0,[],ProveedorNombre:"Cliente");
var movements=monthly.Select(x=>new ZeusMovement(new ZeusAccount("CLIENTE","130505"),x.Valor,
    VencimientoCartera:x.Vencimiento.ToDateTime(TimeOnly.MinValue),NumeroCuota:x.Numero))
    .Append(new ZeusMovement(new ZeusAccount("INGRESO","413502001"),-1200m)).ToArray();
var snapshot=new ZeusSnapshot(settings,source,new ZeusSupplier(1,"123","123"),movements,
    ClienteDocumento:new ZeusCustomerDocument("FACTURA","Venta","130505",FacturaUsaConsecutivoZeus:true,CarteraConsecutivoCompleto:true));
var xml=XElement.Parse(ZeusXml.Build(snapshot,Guid.NewGuid(),"0000000060"));
var receivables=xml.Descendants("Transac").Where(x=>(string?)x.Element("CODICTA")=="130505").ToArray();
Check(receivables.Length==12&&receivables.Select(x=>(string?)x.Element("VENCEFAC")).Distinct().Count()==12,
    "Zeus recibe doce movimientos de cuenta 13 con vencimientos separados");
Check((string?)receivables[0].Element("VENCEFAC")=="2026/10/03"
    &&(string?)receivables[1].Element("VENCEFAC")=="2026/11/03", "Zeus conserva el día mensual y el número de factura");
Check(receivables.All(x=>(string?)x.Element("NUMEFAC")=="0000000060")
    &&(string?)xml.Descendants("Document").Single().Element("NUMEDCTO")=="0000000060",
    "las doce cuotas usan el consecutivo del comprobante Zeus");
Check((string?)xml.Descendants("Transac").Single(x=>(string?)x.Element("CODICTA")=="413502001").Element("NUMEFAC")=="FV-1",
    "la referencia interna del ERP no sustituye el número de cartera");
var previousFormat=XElement.Parse(ZeusXml.Build(snapshot with{ClienteDocumento=snapshot.ClienteDocumento! with{CarteraConsecutivoCompleto=false}},Guid.NewGuid(),"0000000060"));
Check(previousFormat.Descendants("Transac").Where(x=>(string?)x.Element("CODICTA")=="130505")
    .All(x=>(string?)x.Element("NUMEFAC")=="00000060"),"los comprobantes ya enviados con ocho dígitos conservan su referencia de cobro");
var legacy=XElement.Parse(ZeusXml.Build(snapshot with{ClienteDocumento=snapshot.ClienteDocumento! with{FacturaUsaConsecutivoZeus=false}},Guid.NewGuid()));
Check(legacy.Descendants("Transac").Where(x=>(string?)x.Element("CODICTA")=="130505")
    .All(x=>(string?)x.Element("NUMEFAC")=="FV-1"),"los snapshots históricos conservan su numeración");

var days=SalesInstallments.Build(new DateOnly(2026,10,3),3,SalesInstallments.EveryThirtyDays,100.01m);
Check(days[1].Vencimiento==new DateOnly(2026,11,2)&&days[2].Vencimiento==new DateOnly(2026,12,2),"intervalos reales de treinta días");
Check(days[0].Valor==33.33m&&days[1].Valor==33.33m&&days[2].Valor==33.35m
    &&days.Sum(x=>x.Valor)==100.01m,"última cuota ajustada al centavo");

var monthEnd=SalesInstallments.Build(new DateOnly(2027,1,31),3,SalesInstallments.SameDayMonthly,3m);
Check(monthEnd[1].Vencimiento==new DateOnly(2027,2,28)
    &&monthEnd[2].Vencimiento==new DateOnly(2027,3,31),"fin de mes anclado al día inicial");
Check(SalesInstallments.Build(new DateOnly(2026,10,3),1,SalesInstallments.SameDayMonthly,0m).Length==0,
    "sin saldo no se crean partidas de cartera");
try{SalesInstallments.Build(new DateOnly(2026,10,3),12,SalesInstallments.SameDayMonthly,0.10m);throw new Exception("No rechazó cuotas inferiores a un centavo.");}
catch(ArgumentException){Console.WriteLine("OK: saldo insuficiente rechazado");}
