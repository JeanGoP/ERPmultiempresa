namespace NexoERP.Api.Sales;

public static class CustomerPaymentPolicy
{
    public static void ValidateDueDate(DateTime dueDate,DateOnly paymentDate)
    {
        if(DateOnly.FromDateTime(dueDate)>paymentDate)
            throw new ArgumentException("No se pueden recaudar cuotas futuras. Selecciona una cuota vencida a la fecha del recibo.");
    }
}
