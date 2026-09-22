using NexoERP.Api.Zeus;

static class LineRoundingTests
{
    public static string Xml(string quantity,string price,string net,string extra="")=>$"<Invoice><InvoiceLine><ID>2</ID><InvoicedQuantity>{quantity}</InvoicedQuantity><LineExtensionAmount>{net}</LineExtensionAmount>{extra}<Price><PriceAmount>{price}</PriceAmount></Price></InvoiceLine></Invoice>";
    public static void Run(Action<bool,string> check,ZeusSettings settings,ZeusSource source)
    {
        var xml=Xml("2","37177.00","74353.00");
        check(ZeusLineRounding.Matches(xml,2,74353,74354,0,0),"XML conserva neto 74353 frente a precio unitario entero redondeado");
        check(ZeusLineRounding.Matches(Xml("5","125714.00","628572"),2,628572,628570,0,0),"XML admite diferencia de dos pesos para cinco unidades");
        check(ZeusLineRounding.Matches("<AttachedDocument><Attachment><ExternalReference><Description><![CDATA["+xml+"]]></Description></ExternalReference></Attachment></AttachedDocument>",2,74353,74354,0,0),"Misma regla para factura embebida AttachedDocument");
        check(ZeusLineRounding.Matches(Xml("3","10.12","30.35"),2,30.35m,30.36m,0,0),"Precio con centavos admite su margen multiplicado por cantidad");
        check(!ZeusLineRounding.Matches(Xml("3","10.12","30.00"),2,30,30.36m,0,0),"Precio decimal no hereda tolerancia de precio entero");
        check(!ZeusLineRounding.Matches(xml,2,74352,74354,0,0),"No acepta neto ERP distinto del XML");
        check(!ZeusLineRounding.Matches(Xml("2","37177","74350"),2,74350,74354,0,0),"Rechaza diferencias mayores al margen justificable");
        check(!ZeusLineRounding.Matches(xml,1,74353,74354,0,0),"No toma neto de otra linea");
        check(!ZeusLineRounding.Matches(xml,2,74353,74355,0,0),"Subtotal debe coincidir con cantidad por precio del XML");
        check(!ZeusLineRounding.Matches(null,2,74353,74354,0,0),"Sin XML no se inventa tolerancia");
        check(!ZeusLineRounding.Matches("<!DOCTYPE Invoice [<!ENTITY x SYSTEM 'file:///secret'>]>"+xml,2,74353,74354,0,0),"No permite entidades externas XML");
        var discount="<AllowanceCharge><ChargeIndicator>false</ChargeIndicator><Amount>10</Amount></AllowanceCharge>";
        check(ZeusLineRounding.Matches(Xml("2","37177","74343",discount),2,74343,74354,10,0),"Descuentos declarados se conservan sin duplicacion");
        check(!ZeusLineRounding.Matches(Xml("2","37177","74343",discount),2,74343,74354,9,0),"Descuento guardado debe coincidir con XML");
        var charge="<AllowanceCharge><ChargeIndicator>true</ChargeIndicator><Amount>10</Amount></AllowanceCharge>";
        check(ZeusLineRounding.Matches(Xml("2","37177","74363",charge),2,74363,74354,0,10),"Cargos declarados se conservan una sola vez");
        check(!ZeusLineRounding.Matches(xml.Replace("</Invoice>",xml.Replace("<Invoice>","").Replace("</Invoice>","")+"</Invoice>"),2,74353,74354,0,0),"Identificador de linea duplicado se rechaza");
        var bases=new[]{23353m,74353m,82354m,125714m,628572m,9343m};
        var taxes=new[]{4437m,14127m,15647m,23886m,119429m,1775m};
        var invoice=source with{Factura="192402683",Total=1122990,Impuestos=179301,Retenciones=0,Lineas=bases.Select(b=>new ZeusSourceLine(50,b)).ToArray()};
        var journal=ZeusJournal.Build(settings,invoice,new(bases.Select((b,i)=>new ZeusTax("IVA",19,b,taxes[i])).ToArray(),[]));
        check(journal.Movimientos.Sum(m=>m.Valor)==0&&journal.Movimientos.Last().Valor==-1122990,"192402683 cuadra 1122990 con netos XML sin cambiar inventario ni cartera");
    }
}
