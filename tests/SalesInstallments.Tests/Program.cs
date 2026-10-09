using NexoERP.Api.Sales;
using NexoERP.Api.Zeus;
using System.Xml.Linq;

static void Check(bool condition,string description)
{
    if(!condition)throw new Exception(description);
    Console.WriteLine("OK: "+description);
}

SalesPricing.Validate(95m,100m,5m,70m,19m,true,1);
Check(true,"descuento exacto al límite permitido");
try{SalesPricing.Validate(94.99m,100m,5m,70m,19m,true,1);throw new Exception("Permitió exceso de descuento.");}
catch(ArgumentException){Console.WriteLine("OK: descuento superior al límite bloqueado");}
try{SalesPricing.Validate(95m,100m,5m,90m,19m,true,1);throw new Exception("Permitió vender bajo costo.");}
catch(ArgumentException){Console.WriteLine("OK: venta bajo costo bloqueada incluso con descuento permitido");}
SalesPricing.Validate(100m,null,0m,80m,19m,true,1);
Check(true,"artículo sin precio de lista puede venderse sobre costo");
var priceExceptions=SalesPricing.Assess(80m,100m,5m,90m,19m,true,7,2);
Check(priceExceptions.Length==2&&priceExceptions.Any(x=>x.Tipo=="DESCUENTO"&&x.Umbral==95m)
    &&priceExceptions.Any(x=>x.Tipo=="BAJO_COSTO"&&x.Umbral==107.10m),"solicitud separa exceso de descuento y venta bajo costo");
Check(SalesPricing.Assess(95m,null,5m,60m,19m,true,7,2,"Artículo",100m,5m).Length==0,
    "descuento explícito dentro del límite sin precio de lista");
Check(SalesPricing.Assess(90m,null,5m,60m,19m,true,7,2,"Artículo",100m,10m)
    .Any(x=>x.Tipo=="DESCUENTO"&&x.Umbral==95m),"descuento explícito excesivo requiere autorización sin precio de lista");
try{SalesPricing.Assess(94m,null,5m,60m,19m,true,7,2,"Artículo",100m,5m);throw new Exception("Permitió un precio final distinto del descuento declarado.");}
catch(ArgumentException){Console.WriteLine("OK: el precio final debe coincidir con el descuento declarado");}
var approvalInvoice=new SalesInvoiceInput(Guid.NewGuid(),"FV-AUT-1",3,2,new DateOnly(2026,10,8),new DateOnly(2026,11,8),
    [new SaleItem(7,2,1m,80m,null)],[],1,SalesInstallments.SameDayMonthly,[],null,null,"MOTO",null,null);
var originalHash=SalesPriceApprovalRepository.Hash(approvalInvoice);
Check(originalHash==SalesPriceApprovalRepository.Hash(approvalInvoice with{AutorizacionVentaId=9}),"identificador de autorización no modifica la huella aprobada");
Check(originalHash!=SalesPriceApprovalRepository.Hash(approvalInvoice with{Lineas=[new SaleItem(7,2,1m,79m,null)]}),
    "la aprobación no sirve para un precio alterado");
Check(originalHash!=SalesPriceApprovalRepository.Hash(approvalInvoice with{Lineas=[new SaleItem(7,2,1m,80m,null,100m,20m)]}),
    "la aprobación conserva la base y el porcentaje de descuento");

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

var noteSnapshot=new ZeusSnapshot(settings with{Fuente="09"},source,new ZeusSupplier(1,"BUR0002","1063281836"),
    [new(new ZeusAccount("CLIENTE","130505001"),-150800m,VencimientoCartera:new DateTime(2026,10,25),NumeroCuota:1),
     new(new ZeusAccount("CLIENTE","130505001"),-233000m,VencimientoCartera:new DateTime(2026,11,25),NumeroCuota:2),
     new(new ZeusAccount("CLIENTE","130505001"),203000m,VencimientoCartera:new DateTime(2026,12,28),NumeroCuota:1),
     new(new ZeusAccount("CLIENTE","130505001"),203000m,VencimientoCartera:new DateTime(2027,1,28),NumeroCuota:2),
     new(new ZeusAccount("REFINANCIACION_INGRESO","421025001"),-22200m)],
    NotaCartera:new ZeusPortfolioNote("FA","0000000060","Local","Cambio de plazo"));
var noteXml=XElement.Parse(ZeusXml.Build(noteSnapshot,Guid.NewGuid()));
var noteLines=noteXml.Descendants("Transac").ToArray();
Check(noteLines.Length==5&&noteLines.Sum(x=>decimal.Parse((string)x.Element("VALORTRA")!,System.Globalization.CultureInfo.InvariantCulture))==0m,
    "nota de cartera balanceada con cuotas anteriores, nuevas y diferencia de ingreso");
Check(noteLines.Where(x=>(string?)x.Element("INDCPITRA")=="2").All(x=>(string?)x.Element("NUMEFAC")=="0000000060"&&(string?)x.Element("TIPOFAC")=="FA"&&(string?)x.Element("CLIPRV")=="BUR0002"),
    "las cuotas de la nota conservan la referencia original y cliente Zeus");
Check(noteLines.Single(x=>(string?)x.Element("CODICTA")=="421025001").Element("NUMEFAC")!.Value=="" &&
    (string?)noteXml.Descendants("Document").Single().Element("XmlAdicionales") is string marker && marker.StartsWith("NEXO:"),
    "el ingreso de financiación no crea una nueva factura y la nota conserva idempotencia");

var days=SalesInstallments.Build(new DateOnly(2026,10,3),3,SalesInstallments.EveryThirtyDays,100.01m);
Check(days[1].Vencimiento==new DateOnly(2026,11,2)&&days[2].Vencimiento==new DateOnly(2026,12,2),"intervalos reales de treinta días");
Check(days[0].Valor==33.33m&&days[1].Valor==33.33m&&days[2].Valor==33.35m
    &&days.Sum(x=>x.Valor)==100.01m,"última cuota ajustada al centavo");

var monthEnd=SalesInstallments.Build(new DateOnly(2027,1,31),3,SalesInstallments.SameDayMonthly,3m);
Check(monthEnd[1].Vencimiento==new DateOnly(2027,2,28)
    &&monthEnd[2].Vencimiento==new DateOnly(2027,3,31),"fin de mes anclado al día inicial");
Check(SalesInstallments.Build(new DateOnly(2026,10,3),1,SalesInstallments.SameDayMonthly,0m).Length==0,
    "sin saldo no se crean partidas de cartera");
var mixed=SalesInstallments.BuildWithExtras(new DateOnly(2026,10,3),2,SalesInstallments.SameDayMonthly,1300m,
    new DateOnly(2026,9,30),[new SalesExtraInstallment(new DateOnly(2026,10,15),300m)]);
Check(mixed.Length==3&&mixed.Sum(x=>x.Valor)==1300m&&mixed[0].Valor==500m&&mixed[1].Tipo=="EXTRA"
    &&mixed[1].Vencimiento==new DateOnly(2026,10,15)&&mixed[2].Numero==3,
    "cuota extraordinaria con vencimiento propio y reparto exacto del saldo ordinario");
try{SalesInstallments.BuildWithExtras(new DateOnly(2026,10,3),2,SalesInstallments.SameDayMonthly,300m,
    new DateOnly(2026,9,30),[new SalesExtraInstallment(new DateOnly(2026,10,15),300m)]);
    throw new Exception("Permitió cuotas extras sin saldo para las ordinarias.");}
catch(ArgumentException){Console.WriteLine("OK: extras no consumen el saldo de cuotas ordinarias");}
try{SalesInstallments.Build(new DateOnly(2026,10,3),12,SalesInstallments.SameDayMonthly,0.10m);throw new Exception("No rechazó cuotas inferiores a un centavo.");}
catch(ArgumentException){Console.WriteLine("OK: saldo insuficiente rechazado");}
CustomerPaymentPolicy.ValidateDueDate(new DateTime(2026,10,3),new DateOnly(2026,10,3));
CustomerPaymentPolicy.ValidateDueDate(new DateTime(2026,10,3),new DateOnly(2026,10,4));
try{CustomerPaymentPolicy.ValidateDueDate(new DateTime(2026,10,4),new DateOnly(2026,10,3));throw new Exception("Permitió cobrar una cuota futura.");}
catch(ArgumentException){Console.WriteLine("OK: no recauda cuotas antes del vencimiento");}
