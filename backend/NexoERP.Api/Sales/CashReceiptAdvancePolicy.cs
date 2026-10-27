namespace NexoERP.Api.Sales;

public static class CashReceiptAdvancePolicy
{
    public static CashReceiptConcept[] Normalize(CashReceiptConcept[]? lines,decimal total)
    {
        var normalized=lines is {Length:>0}?lines:[new CashReceiptConcept("ANTICIPO",total)];
        if(normalized.Length>4||normalized.Any(x=>x is null||x.Codigo is not("ANTICIPO" or "SOAT" or "MATRICULA" or "OTROS")
            ||x.Valor<=0||decimal.Round(x.Valor,2)!=x.Valor)
            ||normalized.Select(x=>x.Codigo).Distinct().Count()!=normalized.Length
            ||normalized.Sum(x=>x.Valor)!=total)
            throw new ArgumentException("Los valores de anticipo, SOAT, matrícula y otros deben ser positivos, únicos y sumar el total recibido.");
        return normalized;
    }
    public static decimal PurchaseAmount(IEnumerable<CashReceiptConcept> lines)=>lines.Where(x=>x.Codigo=="ANTICIPO").Sum(x=>x.Valor);
}
