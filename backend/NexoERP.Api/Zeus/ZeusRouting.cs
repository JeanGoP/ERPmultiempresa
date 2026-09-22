namespace NexoERP.Api.Zeus;

public sealed record ZeusSourceRoute(string Sucursal,string Movimiento,string Fuente,string Serie,long[] Usuarios,
    [property:System.Text.Json.Serialization.JsonIgnore(Condition=System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] long? SucursalId=null,
    [property:System.Text.Json.Serialization.JsonIgnore(Condition=System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] string? UnidadNegocio=null,
    [property:System.Text.Json.Serialization.JsonIgnore(Condition=System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)] string? TipoFactura=null);
public static class ZeusRouting
{
    public static readonly string[] Movements=["ENTRADA_MERCANCIA","FACTURACION","RECIBO_CAJA","EGRESO"];
    public static void Validate(ZeusSourceRoute[]? routes)
    {
        if(routes is null)return;
        if(routes.Length>200)throw new ArgumentException("Máximo 200 reglas de fuentes por empresa.");
        foreach(var r in routes)
            if(r is null||string.IsNullOrWhiteSpace(r.Sucursal)||r.Sucursal.Length>80||r.Sucursal.Any(char.IsControl)
                ||!Movements.Contains(r.Movimiento)||r.Fuente is null||r.Fuente.Length!=2||r.Fuente.Any(c=>!char.IsAsciiLetterOrDigit(c))
                ||r.Serie is null||r.Serie.Length!=2||r.Serie.Any(c=>!char.IsAsciiDigit(c))||r.Usuarios is null
                ||r.UnidadNegocio is not null&&(string.IsNullOrWhiteSpace(r.UnidadNegocio)||r.UnidadNegocio.Length>20||r.UnidadNegocio.Any(char.IsControl))
                ||r.TipoFactura is not null&&(string.IsNullOrWhiteSpace(r.TipoFactura)||r.TipoFactura.Length>10||r.TipoFactura.Any(char.IsControl))
                ||r.SucursalId is <=0||r.Usuarios.Length>1000||r.Usuarios.Any(u=>u<=0)||r.Usuarios.Distinct().Count()!=r.Usuarios.Length)
                throw new ArgumentException("Revisa sucursal, movimiento, fuente de dos caracteres, serie de dos dígitos y usuarios de cada regla.");
        foreach(var group in routes.GroupBy(r=>r.Movimiento))
        {
            if(group.GroupBy(r=>r.Sucursal.Trim(),StringComparer.OrdinalIgnoreCase).Any(g=>g.Select(r=>(r.Fuente,r.Serie,r.UnidadNegocio,r.TipoFactura)).Distinct().Count()>1))
                throw new ArgumentException("Una sucursal debe tener la misma fuente y serie para el mismo movimiento.");
            if(group.Where(r=>r.SucursalId.HasValue).GroupBy(r=>r.SucursalId).Any(g=>g.Select(r=>(r.Fuente,r.Serie,r.UnidadNegocio,r.TipoFactura)).Distinct().Count()>1))
                throw new ArgumentException("Cada sucursal y movimiento admite una sola fuente y serie.");
        }
    }
    public static ZeusSettings Resolve(ZeusSettings settings,long branch,string movement,string? branchName=null)
    {
        Validate(settings.FuentesAutomaticas);
        var rules=(settings.FuentesAutomaticas??[]).Where(r=>r.Movimiento==movement).ToArray();
        if(rules.Length==0)return settings;
        var route=rules.FirstOrDefault(r=>r.SucursalId==branch||r.SucursalId is null&&string.Equals(r.Sucursal.Trim(),branchName?.Trim(),StringComparison.OrdinalIgnoreCase))
            ??throw new ArgumentException("La sucursal no tiene fuente para este movimiento. Configúrala en Integración Zeus → Fuentes automáticas.");
        return settings with{Fuente=route.Fuente,Serie=route.Serie,SucursalOperacion=route.Sucursal,UnidadNegocio=route.UnidadNegocio??settings.UnidadNegocio,TipoFactura=route.TipoFactura??settings.TipoFactura};
    }
}
