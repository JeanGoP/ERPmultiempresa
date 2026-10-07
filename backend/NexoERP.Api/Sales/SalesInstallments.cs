namespace NexoERP.Api.Sales;

public sealed record SalesInstallment(int Numero,DateOnly Vencimiento,decimal Valor);

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
}
