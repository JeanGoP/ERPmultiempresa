namespace NexoERP.Api.Sales;

public static class CustomerPaymentPolicy
{
    public sealed record OpenInstallment(long InvoiceId,long InstallmentId,DateTime DueDate,int Number,decimal Balance);

    public static void ValidateOrder(IReadOnlyList<OpenInstallment> open,IReadOnlyList<CashReceiptApplication> applications)
    {
        var chosen=applications.Where(x=>x.FacturaVentaCuotaId.HasValue)
            .ToDictionary(x=>(x.FacturaVentaId,x.FacturaVentaCuotaId!.Value),x=>x.Valor);
        foreach(var invoice in open.GroupBy(x=>x.InvoiceId))
        {
            var earlierUnpaid=false;
            foreach(var due in invoice.OrderBy(x=>x.DueDate).ThenBy(x=>x.Number).ThenBy(x=>x.InstallmentId))
            {
                chosen.TryGetValue((due.InvoiceId,due.InstallmentId),out var paid);
                if(earlierUnpaid&&paid>0)
                    throw new ArgumentException("Paga primero las cuotas anteriores de la misma factura, por orden de vencimiento. Puedes anticipar la siguiente cuota aunque todavía no venza.");
                if(paid<due.Balance)earlierUnpaid=true;
            }
        }
    }
}
