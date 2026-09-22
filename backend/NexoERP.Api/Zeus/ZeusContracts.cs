using System.Globalization;

namespace NexoERP.Api.Zeus;

public sealed record ZeusAccount(string Concepto, string Cuenta, decimal? Tarifa = null, long? ArticuloId = null,
    long? ProveedorId = null, string CentroCosto = "", string Auxiliar = "", string Item = "",
    string Presupuesto = "", string Reserva = "");
public sealed record ZeusSupplier(long ProveedorId, string CodigoProveedor, string CodigoTercero);
public sealed record ZeusSettings(bool Habilitado, string ServidorEsperado, string BaseEsperada, string Fuente,
    string Serie, string UnidadNegocio, string UsuarioZeus, string TipoFactura,
    ZeusAccount[] Cuentas, ZeusSupplier[] Proveedores);
public sealed record ZeusSettingsRequest(int Version, ZeusSettings Configuracion);
public sealed record ZeusTax(string Concepto, decimal Tarifa, decimal Base, decimal Valor,long? BodegaId=null);
public sealed record ZeusPreviewRequest(ZeusTax[] Impuestos, ZeusTax[] Retenciones);
public sealed record ZeusApproveRequest(ZeusTax[] Impuestos, ZeusTax[] Retenciones, string Huella);
public sealed record ZeusSourceLine(long ArticuloId, decimal Base,long? BodegaId=null,string? CuentaInventario=null,string? CuentaIvaCompras=null);
public sealed record ZeusSource(long RecepcionId, long ProveedorId, string Factura, DateTime FechaContable,
    DateTime FechaFactura, DateTime Vencimiento, decimal Total, decimal Impuestos, decimal Retenciones,
    ZeusSourceLine[] Lineas,string? DivisionPoliticaZeus=null,
    [property:System.Text.Json.Serialization.JsonIgnore(Condition=System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] string? ProveedorNombre=null);
public sealed record ZeusMovement(ZeusAccount Regla, decimal Valor, decimal Base = 0, decimal Tarifa = 0,long? BodegaId=null);
public sealed record ZeusSnapshot(ZeusSettings Configuracion, ZeusSource Origen, ZeusSupplier Proveedor,
    ZeusMovement[] Movimientos);

public static class ZeusJournal
{
    public static bool IsRetention(string concept)=>concept is "RETEFUENTE" or "RETEIVA" or "RETEICA";
    public static void ValidateRetentionAccounts(ZeusSettings settings,IEnumerable<ZeusChartAccount> chart)
    {
        var actual=WithZeusRetentionRates(settings,chart);
        if(!settings.Cuentas.SequenceEqual(actual.Cuentas))throw new ArgumentException("La tarifa de retención no coincide con PORCEIMPUESTO de Zeus. Actualiza y guarda nuevamente la configuración.");
    }
    public static ZeusSettings WithZeusRetentionRates(ZeusSettings settings,IEnumerable<ZeusChartAccount> chart)
    {
        var allowed=chart.ToDictionary(a=>a.Codigo,StringComparer.Ordinal);
        var result=settings with{Cuentas=settings.Cuentas.Select(rule=>
        {
            if(!IsRetention(rule.Concepto))return rule;
            if(!allowed.TryGetValue(rule.Cuenta,out var account)||account.Tarifa is null or <=0 or >100||account.BaseEsValorRetenido!=false||decimal.Round(account.Tarifa.Value,4)!=account.Tarifa.Value)
                throw new ArgumentException($"La cuenta {rule.Cuenta} de {rule.Concepto} no informa un porcentaje compatible en Zeus (PORCEIMPUESTO), o utiliza base de valor retenido. Revisa el plan de cuentas; no se deduce ni redondea la tarifa.");
            return rule with{Tarifa=account.Tarifa};
        }).ToArray()};
        Validate(result);return result;
    }
    public static ZeusAccount? GeneralSupplierAccount(ZeusSettings settings)
    {
        Validate(settings);
        var rules=settings.Cuentas.Where(a=>a.Concepto=="PROVEEDOR").ToArray();
        if(rules.Length>1||rules.Any(a=>a.ArticuloId is not null||a.ProveedorId is not null||a.Tarifa is not null))
            throw new ArgumentException("La cuenta por pagar a proveedores debe ser una única cuenta general de la empresa, sin artículo, proveedor ni tarifa específicos.");
        if(settings.Habilitado&&rules.Length==0)
            throw new ArgumentException("Selecciona la cuenta general por pagar a proveedores antes de habilitar aprobaciones.");
        return rules.SingleOrDefault();
    }
    public static readonly string[] Concepts = ["INVENTARIO", "PROVEEDOR", "CUENTA_POR_COBRAR", "IVA",
        "OTRO_IMPUESTO", "RETEFUENTE", "RETEIVA", "RETEICA", "GASTO", "FLETE", "ANTICIPO", "DESCUENTO", "REDONDEO"];
    public static void Validate(ZeusSettings s)
    {
        Text(s.ServidorEsperado, 150); Text(s.BaseEsperada, 128); Text(s.Fuente, 2);
        if(s.Fuente.Length != 2 || s.Serie is null || s.Serie.Length != 2 || s.Serie.Any(c=>c<'0'||c>'9'))
            throw new ArgumentException("Fuente y serie deben tener dos caracteres; la serie debe ser numérica.");
        Text(s.UnidadNegocio, 20); Text(s.UsuarioZeus, 20); Text(s.TipoFactura, 10);
        if(s.Cuentas is null || s.Proveedores is null || s.Cuentas.Length>2000 || s.Proveedores.Length>10000)
            throw new ArgumentException("Configuración de cuentas y proveedores inválida.");
        foreach(var a in s.Cuentas)
        {
            if(a is null || !Concepts.Contains(a.Concepto) || a.Tarifa is <0 or >100 || (a.Tarifa.HasValue && decimal.Round(a.Tarifa.Value,4)!=a.Tarifa.Value) || a.ArticuloId is <=0 || a.ProveedorId is <=0)
                throw new ArgumentException("Regla contable inválida.");
            Text(a.Cuenta, 20); Text(a.CentroCosto, 20, true); Text(a.Auxiliar, 20, true);
            Text(a.Item, 20, true); Text(a.Presupuesto, 20, true); Text(a.Reserva, 20, true);
        }
        if(s.Cuentas.GroupBy(a=>(a.Concepto,a.Tarifa,a.ArticuloId,a.ProveedorId)).Any(g=>g.Count()>1))
            throw new ArgumentException("Hay reglas contables duplicadas.");
        if(s.Proveedores.Any(p=>p is null || p.ProveedorId<=0) || s.Proveedores.GroupBy(p=>p.ProveedorId).Any(g=>g.Count()>1))
            throw new ArgumentException("Proveedores inválidos o duplicados.");
        foreach(var p in s.Proveedores) { Text(p.CodigoProveedor, 20); Text(p.CodigoTercero, 20); }
    }
    private static void Text(string? value, int max, bool empty=false)
    {
        if(value is null || (!empty && string.IsNullOrWhiteSpace(value)) || value.Length>max || value.Any(char.IsControl))
            throw new ArgumentException($"Código obligatorio o longitud inválida (máximo {max}).");
    }
    public static ZeusSnapshot Build(ZeusSettings s, ZeusSource source, ZeusPreviewRequest input)
    {
        Validate(s);
        if(input.Impuestos is null || input.Retenciones is null || input.Impuestos.Length+input.Retenciones.Length>100)
            throw new ArgumentException("Envía el desglose de impuestos y retenciones, incluso si está vacío.");
        input=new(ZeusTaxRounding.Normalize(input.Impuestos,false,source.Impuestos),ZeusTaxRounding.Normalize(input.Retenciones,true,source.Retenciones));
        var supplier=s.Proveedores.SingleOrDefault(p=>p.ProveedorId==source.ProveedorId)
            ?? throw new ArgumentException("Falta homologar el proveedor y tercero de Zeus.");
        if(source.Factura.Length>20) throw new ArgumentException("La factura excede los 20 caracteres admitidos por este adaptador.");
        ZeusAccount Resolve(string concept, long? article=null, decimal? rate=null)
        {
            var rules=s.Cuentas.Where(a=>a.Concepto==concept && (a.Tarifa==rate||(IsRetention(concept)&&a.Tarifa is null))
                && (a.ArticuloId is null || a.ArticuloId==article)
                && (a.ProveedorId is null || a.ProveedorId==source.ProveedorId))
                .OrderByDescending(a=>(a.Tarifa==rate?4:0)+(a.ArticuloId.HasValue?2:0)+(a.ProveedorId.HasValue?1:0)).ToArray();
            return rules.FirstOrDefault() ?? throw new ArgumentException(IsRetention(concept)?$"Falta la cuenta de {concept} para la tarifa {Number(rate??0)} %. Configúrala en Integración Zeus → Configuración de empresa → Retenciones.":$"Falta cuenta para {concept}, artículo {article}, tarifa {rate}.");
        }
        var lines=new List<ZeusMovement>();
        foreach(var line in source.Lineas)
        {
            if(line.Base<=0 || decimal.Round(line.Base,2)!=line.Base)
                throw new ArgumentException("Esta versión requiere bases positivas con máximo dos decimales; revisa descuentos y redondeos.");
            lines.Add(new(line.CuentaInventario is null?Resolve("INVENTARIO",line.ArticuloId):new ZeusAccount("INVENTARIO",line.CuentaInventario),line.Base,BodegaId:line.BodegaId));
        }
        void Taxes(ZeusTax[] taxes, bool withholding)
        {
            foreach(var tax in taxes)
            {
                ZeusAccount rule;long? warehouse=null;
                if(tax.Concepto=="IVA"&&source.Lineas.Any(l=>l.CuentaIvaCompras is not null))
                {
                    var candidates=source.Lineas.Where(l=>tax.BodegaId is null||l.BodegaId==tax.BodegaId).ToArray();
                    if(candidates.Length==0||candidates.Any(l=>l.CuentaIvaCompras is null)||candidates.Select(l=>l.CuentaIvaCompras).Distinct().Count()!=1)
                        throw new ArgumentException("Distribuye el IVA por bodega en el desglose: las bodegas tienen cuentas de IVA distintas.");
                    rule=new ZeusAccount("IVA",candidates[0].CuentaIvaCompras!,tax.Tarifa);warehouse=tax.BodegaId;
                }
                else
                {
                    if(tax.BodegaId is not null)throw new ArgumentException("La asignación por bodega solo aplica al IVA de compras con cuentas de bodega configuradas.");
                    rule=Resolve(tax.Concepto,rate:tax.Tarifa);
                }
                lines.Add(new(rule,withholding?-tax.Valor:tax.Valor,withholding?-tax.Base:tax.Base,tax.Tarifa,warehouse));
            }
        }
        Taxes(input.Impuestos,false); Taxes(input.Retenciones,true);
        foreach(var allocation in input.Impuestos.Where(t=>t.Concepto=="IVA"&&t.BodegaId.HasValue).GroupBy(t=>t.BodegaId))
            if(allocation.Sum(t=>t.Base)>source.Lineas.Where(l=>l.BodegaId==allocation.Key).Sum(l=>l.Base))
                throw new ArgumentException("La base de IVA asignada supera el valor de mercancía de esa bodega.");
        if(input.Impuestos.Sum(t=>t.Valor)!=source.Impuestos || input.Retenciones.Sum(t=>t.Valor)!=source.Retenciones)
            throw new ArgumentException("El desglose no coincide con los impuestos o retenciones guardados en la factura.");
        if(source.Total<=0 || lines.Sum(l=>l.Valor)!=source.Total)
            throw new ArgumentException("Las bases, impuestos y retenciones no cuadran con el total por pagar. No se generan ajustes automáticos.");
        lines.Add(new(Resolve("PROVEEDOR"),-source.Total));
        return new(s,source,supplier,lines.ToArray());
    }
    public static string Number(decimal value)=>value.ToString("0.####",CultureInfo.InvariantCulture);
}
