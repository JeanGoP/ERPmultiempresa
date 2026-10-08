namespace NexoERP.Api.Sales;

public sealed record SalesInstallment(int Numero,DateOnly Vencimiento,decimal Valor,string Tipo="ORDINARIA");
public sealed record SalesExtraInstallment(DateOnly Vencimiento,decimal Valor);

public static class SalesInstallments
{
    public const string EveryThirtyDays="CADA_30_DIAS";
    public const string SameDayMonthly="DIA_FIJO_MES";

    public static SalesInstallment[] Build(DateOnly first,int count,string? frequency,decimal balance)
    {
        if(first.Year<2000||count is <1 or >120)
            throw new ArgumentException("Indica el primer vencimiento y entre 1 y 120 cuotas.");
        if(frequency is not(EveryThirtyDays or SameDayMonthly))
            throw new ArgumentException("Selecciona si las cuotas vencen cada 30 días o el mismo día de cada mes.");
        if(balance<0||decimal.Round(balance,2)!=balance)
            throw new ArgumentException("El saldo a financiar debe tener máximo dos decimales y no ser negativo.");
        if(balance==0)return [];
        var cents=balance*100;
        if(cents<count)throw new ArgumentException("El saldo a financiar no alcanza para que cada cuota tenga al menos un centavo.");
        var regular=decimal.Floor(cents/count);
        var result=new SalesInstallment[count];
        for(var i=0;i<count;i++)
        {
            var due=frequency==EveryThirtyDays?first.AddDays(checked(30*i)):first.AddMonths(i);
            result[i]=new(i+1,due,(i==count-1?cents-regular*(count-1):regular)/100);
        }
        return result;
    }

    public static SalesInstallment[] BuildWithExtras(DateOnly first,int count,string? frequency,decimal balance,
        DateOnly invoiceDate,IReadOnlyList<SalesExtraInstallment>? extras)
    {
        extras??=[];
        if(extras.Count>30||count+extras.Count>120)
            throw new ArgumentException("La factura admite máximo 30 cuotas extras y 120 vencimientos en total.");
        if(extras.Any(x=>x.Valor<=0||decimal.Round(x.Valor,2)!=x.Valor||x.Vencimiento<invoiceDate)
            ||extras.Select(x=>x.Vencimiento).Distinct().Count()!=extras.Count)
            throw new ArgumentException("Cada cuota extra requiere una fecha distinta, posterior a la factura, y un valor positivo con dos decimales.");
        var ordinaryBalance=balance-extras.Sum(x=>x.Valor);
        if(ordinaryBalance<=0&&balance>0)
            throw new ArgumentException("Las cuotas extras deben dejar saldo para las cuotas ordinarias.");
        var ordinary=Build(first,count,frequency,ordinaryBalance);
        return ordinary.Concat(extras.Select(x=>new SalesInstallment(0,x.Vencimiento,x.Valor,"EXTRA")))
            .OrderBy(x=>x.Vencimiento).ThenBy(x=>x.Tipo=="ORDINARIA"?0:1)
            .Select((x,i)=>x with{Numero=i+1}).ToArray();
    }
}
