namespace NexoERP.Api.Sales;

public static class SalesPricing
{
    public static void Validate(decimal priceWithVat,decimal? listPriceWithVat,decimal maxDiscountPercent,decimal averageCost,decimal vatPercent,bool inventory,long articleId)
    {
        if(priceWithVat<=0||maxDiscountPercent is <0 or >100)throw new ArgumentException("Precio o política de descuentos inválidos.");
        if(listPriceWithVat is >0&&priceWithVat<decimal.Round(listPriceWithVat.Value*(1-maxDiscountPercent/100),2,MidpointRounding.AwayFromZero))
            throw new ArgumentException($"El precio del artículo {articleId} supera el descuento permitido de {maxDiscountPercent:0.##} %. Solicita autorización antes de emitir.");
        if(inventory&&averageCost>0&&priceWithVat<decimal.Round(averageCost*(1+vatPercent/100),2,MidpointRounding.AwayFromZero))
            throw new ArgumentException($"El precio del artículo {articleId} es inferior al costo con IVA. Requiere autorización antes de emitir.");
    }
}
