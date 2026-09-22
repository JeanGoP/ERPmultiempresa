namespace NexoERP.Api.Zeus;

// Importes monetarios del adaptador, no tarifas ni valores persistidos de la factura.
public static class ZeusTaxRounding
{
    public static decimal Money(decimal value)=>decimal.Round(value,2,MidpointRounding.AwayFromZero);
    private static bool Consistent(decimal basis,decimal rate,decimal amount,bool vat)
    {
        var calculated=basis*rate/100;
        return Math.Abs(Money(calculated)-Money(amount))<=0.01m
            ||(vat&&amount==decimal.Truncate(amount)&&amount==decimal.Round(calculated,0,MidpointRounding.AwayFromZero));
    }
    public static ZeusTax[] Normalize(ZeusTax[] taxes,bool withholding,decimal savedTotal)
    {
        foreach(var tax in taxes)
            if(tax is null || !(withholding?ZeusJournal.IsRetention(tax.Concepto):tax.Concepto is "IVA" or "OTRO_IMPUESTO")
                ||tax.Tarifa<=0||tax.Tarifa>100||decimal.Round(tax.Tarifa,4)!=tax.Tarifa||tax.Base<=0||tax.Valor<=0)
                throw new ArgumentException("Impuesto inválido: revisa concepto, base positiva, tarifa (máximo cuatro decimales) y valor positivo.");

        foreach(var group in taxes.GroupBy(t=>(t.Concepto,t.Tarifa)))
        {
            var vat=!withholding&&group.Key.Concepto=="IVA";
            // Un proveedor puede distribuir el redondeo de cabecera entre sus líneas.
            // El grupo debe cuadrar y cada línea permanecer dentro del margen monetario;
            // no se permite compensar errores grandes entre artículos o bodegas.
            var individuallyValid=group.All(t=>Consistent(t.Base,t.Tarifa,t.Valor,vat));
            var groupedValid=Consistent(group.Sum(t=>t.Base),group.Key.Tarifa,group.Sum(t=>t.Valor),vat)
                &&group.All(t=>Math.Abs(Money(t.Base*t.Tarifa/100)-Money(t.Valor))<=(vat?0.50m:0.01m));
            if(!individuallyValid&&!groupedValid)
                throw new ArgumentException($"El impuesto {group.Key.Concepto} al {ZeusJournal.Number(group.Key.Tarifa)} % no corresponde a su base. La diferencia excede el redondeo permitido; revisa el XML. No se modifica el total de la factura.");
        }
        var result=taxes.Select(t=>t with{Base=Money(t.Base),Valor=Money(t.Valor)}).ToArray();
        var roundedSum=result.Sum(t=>t.Valor);
        // Acepta redondeo de la suma o suma de redondeos. Nunca usa el saldo del
        // comprobante como ajuste ilimitado ni altera impuestos ya exactos a centavos.
        if(savedTotal!=Money(savedTotal)||(savedTotal!=Money(taxes.Sum(t=>t.Valor))&&savedTotal!=roundedSum))
            throw new ArgumentException($"El desglose de {(withholding?"retenciones":"impuestos")} no coincide con el total guardado ({ZeusJournal.Number(savedTotal)}), incluso después del redondeo a dos decimales.");
        var residual=savedTotal-roundedSum;
        var direction=Math.Sign(residual);
        var candidates=Enumerable.Range(0,taxes.Length)
            .Where(i=>direction*(taxes[i].Valor-result[i].Valor)>0)
            .OrderByDescending(i=>direction*(taxes[i].Valor-result[i].Valor)).ThenBy(i=>i);
        foreach(var i in candidates)
        {
            if(residual==0)break;
            result[i]=result[i] with{Valor=result[i].Valor+direction*0.01m};
            residual-=direction*0.01m;
        }
        if(residual!=0)throw new ArgumentException("No fue posible distribuir los centavos del impuesto sin alterar el total de la factura.");
        if(result.Any(t=>t.Valor<0||(t.Valor>0&&t.Base<=0)))throw new ArgumentException("La base del impuesto no admite representación positiva en centavos.");
        return result.Where(t=>t.Valor>0).ToArray();
    }
}
