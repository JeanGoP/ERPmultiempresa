namespace NexoERP.Api.Zeus;

public sealed record ZeusSourceRoute(string Sucursal,string Movimiento,string Fuente,string Serie,long[] Usuarios);
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
                ||r.Usuarios.Length>1000||r.Usuarios.Any(u=>u<=0)||r.Usuarios.Distinct().Count()!=r.Usuarios.Length)
                throw new ArgumentException("Revisa sucursal, movimiento, fuente de dos caracteres, serie de dos dígitos y usuarios de cada regla.");
        foreach(var group in routes.GroupBy(r=>r.Movimiento))
        {
            if(group.GroupBy(r=>r.Sucursal.Trim(),StringComparer.OrdinalIgnoreCase).Any(g=>g.Select(r=>(r.Fuente,r.Serie)).Distinct().Count()>1))
                throw new ArgumentException("Una sucursal debe tener la misma fuente y serie para el mismo movimiento.");
            if(group.Count(r=>r.Usuarios.Length==0)>1||group.SelectMany(r=>r.Usuarios).GroupBy(u=>u).Any(g=>g.Count()>1))
                throw new ArgumentException("Cada movimiento admite una sola fuente predeterminada y una sola asignación por usuario.");
        }
    }
    public static ZeusSettings Resolve(ZeusSettings settings,long user,string movement)
    {
        Validate(settings.FuentesAutomaticas);
        var rules=(settings.FuentesAutomaticas??[]).Where(r=>r.Movimiento==movement).ToArray();
        if(rules.Length==0)return settings;
        var route=rules.SingleOrDefault(r=>r.Usuarios.Contains(user))??rules.SingleOrDefault(r=>r.Usuarios.Length==0)
            ??throw new ArgumentException("El usuario no tiene una fuente automática asignada para este movimiento. Configúrala en Integración Zeus → Fuentes automáticas.");
        return settings with{Fuente=route.Fuente,Serie=route.Serie,SucursalOperacion=route.Sucursal};
    }
}
