using NexoERP.Api.Zeus;

static class RoutingTests
{
    public static void Run(Action<bool,string> check,Action<Action,string> reject,ZeusSettings settings)
    {
        check(ZeusRouting.Resolve(settings,1,"ENTRADA_MERCANCIA")==settings,"Empresa sin rutas conserva fuente anterior");
        var configured=settings with{FuentesAutomaticas=[new("Principal","ENTRADA_MERCANCIA","12","00",[],8),new("Norte","ENTRADA_MERCANCIA","13","01",[],7),new("Norte","RECIBO_CAJA","20","00",[],7)]};
        var north=ZeusRouting.Resolve(configured,7,"ENTRADA_MERCANCIA");
        check(north.Fuente=="13"&&north.Serie=="01"&&north.SucursalOperacion=="Norte","Fuente automática por sucursal y movimiento, sin selector de fuentes");
        check(ZeusRouting.Resolve(configured,8,"ENTRADA_MERCANCIA").Fuente=="12","Otra sucursal usa su propia fuente");
        check(ZeusRouting.Resolve(configured,7,"RECIBO_CAJA").Fuente=="20","Movimientos independientes para la misma sucursal");
        reject(()=>ZeusRouting.Resolve(configured,8,"RECIBO_CAJA"),"Sin fuente para sucursal y movimiento no se escoge la de otra sucursal");
        ZeusRouting.Validate([new("A","ENTRADA_MERCANCIA","12","00",[],1),new("B","ENTRADA_MERCANCIA","13","00",[],2)]);
        check(true,"Sucursales distintas admiten fuentes distintas sin usuarios");
        reject(()=>ZeusRouting.Validate([new("A","EGRESO","12","00",[],1),new("B","EGRESO","13","00",[],1)]),"Mismo ID de sucursal no admite fuentes contradictorias");
        reject(()=>ZeusRouting.Validate([new("A","OTRO","12","00",[1])]),"Movimiento desconocido se rechaza");
        reject(()=>ZeusRouting.Validate([new("Norte","EGRESO","12","00",[1]),new(" norte ","EGRESO","13","00",[2])]),"Sucursal no puede tener fuentes contradictorias para el mismo movimiento");
        reject(()=>ZeusRouting.Validate([new("A","EGRESO","1","XX",[1])]),"Validación de longitud y serie numérica");
        check(settings.FuentesAutomaticas is null&&configured.Fuente==settings.Fuente,"Resolver no altera configuración general ni otra empresa");
        var perBranch=settings with{Fuente="",Serie="",UnidadNegocio="",TipoFactura="",FuentesAutomaticas=[new("Norte","ENTRADA_MERCANCIA","13","01",[],7,"NORTE","FC")]};
        ZeusJournal.Validate(perBranch);
        var resolved=ZeusRouting.Resolve(perBranch,7,"ENTRADA_MERCANCIA");
        check(resolved.UnidadNegocio=="NORTE"&&resolved.TipoFactura=="FC","Unidad y tipo de documento se resuelven por sucursal sin generales duplicados");
        check(north.UnidadNegocio==settings.UnidadNegocio&&north.TipoFactura==settings.TipoFactura,"Reglas antiguas conservan unidad y tipo general");
        reject(()=>ZeusJournal.Validate(perBranch with{FuentesAutomaticas=[]}),"Configuración nueva sin fuente de entrada no inventa valores generales");
        reject(()=>ZeusRouting.Validate([new("Norte","ENTRADA_MERCANCIA","13","01",[],7,"","FC")]),"Unidad de negocio vacía no se acepta");
    }
}
