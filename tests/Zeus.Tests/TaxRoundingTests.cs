using System.Xml.Linq;
using NexoERP.Api.Zeus;

static class TaxRoundingTests
{
    public static void Run(Action<bool,string> check,Action<Action,string> reject,ZeusSettings settings,ZeusSource source)
    {
        var bases=new[]{4552218m,3895294m};var amounts=new[]{864921.2691m,740105.7309m};
        var xml=new XElement("Invoice",bases.Select((b,i)=>new XElement("InvoiceLine",new XElement("ID",i+1),
            new XElement("TaxTotal",new XElement("TaxSubtotal",new XElement("TaxableAmount",b),new XElement("TaxAmount",amounts[i]),
            new XElement("TaxCategory",new XElement("Percent",19),new XElement("TaxScheme",new XElement("ID","01")))))))).ToString();
        var parsed=ZeusXmlTaxes.Parse(xml,new Dictionary<string,long?>{{"1",1},{"2",2}},0);
        var invoice=source with{Factura="F660066915",Total=10052539,Impuestos=1605027,Retenciones=0,
            Lineas=[new(50,bases[0],1,"1435","240801"),new(51,bases[1],2,"1436","240802")]};
        var journal=ZeusJournal.Build(settings,invoice,parsed);
        var vat=journal.Movimientos.Where(m=>m.Regla.Concepto=="IVA").ToArray();
        check(vat.Select(m=>m.Valor).SequenceEqual(new[]{864921.27m,740105.73m}),"F660066915 normaliza IVA XML de cuatro decimales a centavos");
        check(vat[0].Regla.Cuenta=="240801"&&vat[1].Regla.Cuenta=="240802"&&vat[0].BodegaId==1&&vat[1].BodegaId==2,"Redondeo conserva distribución y cuentas de cada bodega");
        check(journal.Movimientos.Sum(m=>m.Valor)==0&&journal.Movimientos.Last().Valor==-10052539,"F660066915 cuadra sin alterar total proveedor ni inventario");
        check(parsed.Impuestos[0].Valor==864921.2691m,"Normalización no altera XML ni entrada original");
        check(journal.Movimientos.All(m=>m.Valor==ZeusTaxRounding.Money(m.Valor)&&m.Base==ZeusTaxRounding.Money(m.Base)),"Todos los movimientos enviados usan dos decimales monetarios");
        var again=ZeusJournal.Build(settings,invoice,new(vat.Select(m=>new ZeusTax("IVA",m.Tarifa,m.Base,m.Valor,m.BodegaId)).ToArray(),[]));
        check(ZeusRepository.Fingerprint(journal)==ZeusRepository.Fingerprint(again),"Normalización idempotente al reconstruir snapshot aprobado");
        ZeusTax[] small=[new("IVA",19,1,0.194m,1),new("IVA",19,1,0.194m,2)];
        var upward=ZeusTaxRounding.Normalize(small,false,0.39m);
        check(upward[0].Valor==0.20m&&upward[1].Valor==0.19m,"Centavo positivo se distribuye por residuo y orden estable");
        var downward=ZeusTaxRounding.Normalize([new("IVA",19,1,0.195m),new("IVA",19,1,0.195m)],false,0.39m);
        check(downward[0].Valor==0.19m&&downward[1].Valor==0.20m,"Centavo negativo se distribuye sin duplicarlo");
        check(ZeusTaxRounding.Normalize(small,false,0.38m).Sum(t=>t.Valor)==0.38m,"Admite total calculado como suma de redondeos individuales");
        check(ZeusTaxRounding.Normalize([new("RETEFUENTE",2.5m,100.005m,2.500125m)],true,2.50m).Single().Base==100.01m,"Base monetaria y retención normalizadas sin cambiar tarifa");
        reject(()=>ZeusTaxRounding.Normalize(small,false,0.40m),"No inventa centavos fuera de suma redondeada o redondeos individuales");
        reject(()=>ZeusTaxRounding.Normalize([new("IVA",19,100,18),new("IVA",19,100,20)],false,38),"No compensa diferencias grandes entre bodegas aunque la suma cuadre");
        reject(()=>ZeusTaxRounding.Normalize([new("IVA",19,100,18.9m),new("IVA",5,100,5.1m)],false,24),"No compensa diferencias entre tarifas distintas");
        reject(()=>ZeusTaxRounding.Normalize([new("RETEFUENTE",2.5m,100,3)],true,3),"No extiende tolerancia IVA al peso a las retenciones");
        reject(()=>ZeusTaxRounding.Normalize([new("IVA",19.00001m,100,19)],false,19),"No redondea porcentajes para elegir una cuenta diferente");
        reject(()=>ZeusJournal.Build(settings,invoice with{Total=10052540},parsed),"No modifica saldo del proveedor para forzar comprobante");
    }
}
