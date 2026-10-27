namespace NexoERP.Api.Sales;

public static class LateInterestPolicy
{
    // Tasa mensual sobre el abono a cuotas vencidas; mes comercial de 30 días.
    public static decimal Calculate(DateOnly receiptDate,decimal monthlyRate,IEnumerable<(DateOnly Due,decimal Paid)> applications)
    {
        if(monthlyRate is <0 or >100)throw new ArgumentException("La tasa mensual de mora no es válida.");
        var amount=applications.Sum(item=>item.Paid*monthlyRate*Math.Max(0,receiptDate.DayNumber-item.Due.DayNumber)/3000m);
        return decimal.Round(amount,2,MidpointRounding.AwayFromZero);
    }
}
