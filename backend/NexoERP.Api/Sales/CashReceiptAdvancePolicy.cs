namespace NexoERP.Api.Sales;

public static class CashReceiptAdvancePolicy
{
    public static CashReceiptConcept[] Normalize(CashReceiptConcept[]? lines,decimal total)
    {
        var normalized=lines is {Length:>0}?lines:[new CashReceiptConcept("ANTICIPO",total)];
        if(normalized.Length>100||normalized.Any(x=>x is null||x.Codigo is not("ANTICIPO" or "SOAT" or "MATRICULA" or "LIBRE" or "IMPUESTOS" or "TRASLADOS" or "CENTRALES" or "OTROS")
            ||x.Valor<=0||decimal.Round(x.Valor,2)!=x.Valor
            ||(x.Codigo=="LIBRE"?string.IsNullOrWhiteSpace(x.CuentaZeus)||x.CuentaZeus.Length>16||x.CuentaZeus!=x.CuentaZeus.Trim():x.CuentaZeus is not null))
            ||normalized.Where(x=>x.Codigo!="LIBRE").Select(x=>x.Codigo).Distinct().Count()!=normalized.Count(x=>x.Codigo!="LIBRE")
            ||normalized.Sum(x=>x.Valor)!=total)
            throw new ArgumentException("Los destinos del recibo deben tener valores positivos, únicos y sumar el total recibido.");
        return normalized;
    }
    public static decimal PurchaseAmount(IEnumerable<CashReceiptConcept> lines)=>lines.Where(x=>x.Codigo=="ANTICIPO").Sum(x=>x.Valor);
}
