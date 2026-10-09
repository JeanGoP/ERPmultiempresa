namespace NexoERP.Api.Sales;

public static class SalesPricing
{
    public sealed record ExceptionDetail(string Tipo,long ArticuloId,long BodegaId,decimal Precio,decimal Umbral,
        decimal? PrecioLista,decimal CostoPromedio,decimal Iva,decimal DescuentoLibre,string Articulo);

    public static ExceptionDetail[] Assess(decimal priceWithVat,decimal? listPriceWithVat,decimal maxDiscountPercent,
        decimal averageCost,decimal vatPercent,bool inventory,long articleId,long warehouseId,string articleLabel="",
        decimal? basePriceWithVat=null,decimal discountPercent=0)
    {
        if(priceWithVat<=0||maxDiscountPercent is <0 or >100)throw new ArgumentException("Precio o política de descuentos inválidos.");
        if(discountPercent<0||discountPercent>=100||decimal.Round(discountPercent,2)!=discountPercent
           ||basePriceWithVat is <=0||basePriceWithVat is >0 && decimal.Round(basePriceWithVat.Value,2)!=basePriceWithVat.Value
           ||discountPercent>0&&basePriceWithVat is null
           ||basePriceWithVat is >0&&decimal.Round(basePriceWithVat.Value*(1-discountPercent/100),2,MidpointRounding.AwayFromZero)!=priceWithVat)
            throw new ArgumentException("El descuento no coincide con el precio unitario final con IVA.");
        var issues=new List<ExceptionDetail>();
        if(listPriceWithVat is >0)
        {
            var floor=decimal.Round(listPriceWithVat.Value*(1-maxDiscountPercent/100),2,MidpointRounding.AwayFromZero);
            if(priceWithVat<floor)issues.Add(new("DESCUENTO",articleId,warehouseId,priceWithVat,floor,listPriceWithVat,averageCost,vatPercent,maxDiscountPercent,articleLabel));
        }
        if(discountPercent>maxDiscountPercent&&!issues.Any(x=>x.Tipo=="DESCUENTO"))
        {
            var floor=decimal.Round(basePriceWithVat!.Value*(1-maxDiscountPercent/100),2,MidpointRounding.AwayFromZero);
            issues.Add(new("DESCUENTO",articleId,warehouseId,priceWithVat,floor,listPriceWithVat??basePriceWithVat,averageCost,vatPercent,maxDiscountPercent,articleLabel));
        }
        if(inventory&&averageCost>0)
        {
            var floor=decimal.Round(averageCost*(1+vatPercent/100),2,MidpointRounding.AwayFromZero);
            if(priceWithVat<floor)issues.Add(new("BAJO_COSTO",articleId,warehouseId,priceWithVat,floor,listPriceWithVat,averageCost,vatPercent,maxDiscountPercent,articleLabel));
        }
        return issues.ToArray();
    }
    public static void Validate(decimal priceWithVat,decimal? listPriceWithVat,decimal maxDiscountPercent,decimal averageCost,decimal vatPercent,bool inventory,long articleId)
    {
        var issue=Assess(priceWithVat,listPriceWithVat,maxDiscountPercent,averageCost,vatPercent,inventory,articleId,0).FirstOrDefault();
        if(issue is not null)throw new ArgumentException(issue.Tipo=="DESCUENTO"
            ?$"El precio del artículo {articleId} supera el descuento permitido de {maxDiscountPercent:0.##} %. Solicita autorización antes de emitir."
            :$"El precio del artículo {articleId} es inferior al costo con IVA. Requiere autorización antes de emitir.");
    }
}
