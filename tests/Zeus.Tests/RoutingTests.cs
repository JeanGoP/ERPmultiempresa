using NexoERP.Api.Zeus;

static class RoutingTests
{
    public static void Run(Action<bool,string> check,Action<Action,string> reject,ZeusSettings settings)
    {
        check(ZeusRouting.Resolve(settings,1,"ENTRADA_MERCANCIA")==settings,"Empresa sin rutas conserva fuente anterior");
        var configured=settings with{FuentesAutomaticas=[new("Principal","ENTRADA_MERCANCIA","12","00",[]),new("Norte","ENTRADA_MERCANCIA","13","01",[7]),new("Principal","RECIBO_CAJA","20","00",[7])]};
        var north=ZeusRouting.Resolve(configured,7,"ENTRADA_MERCANCIA");
        check(north.Fuente=="13"&&north.Serie=="01"&&north.SucursalOperacion=="Norte","Fuente automática por usuario y movimiento, sin selector");
        check(ZeusRouting.Resolve(configured,8,"ENTRADA_MERCANCIA").Fuente=="12","Usuario sin excepción usa predeterminada del movimiento");
        check(ZeusRouting.Resolve(configured,7,"RECIBO_CAJA").Fuente=="20","Movimientos independientes para el mismo usuario");
        reject(()=>ZeusRouting.Resolve(configured,8,"RECIBO_CAJA"),"Sin asignación ni predeterminada se bloquea, no se escoge al azar");
        reject(()=>ZeusRouting.Validate([new("A","ENTRADA_MERCANCIA","12","00",[1]),new("B","ENTRADA_MERCANCIA","13","00",[1])]),"Dos sucursales para un usuario y movimiento se rechazan");
        reject(()=>ZeusRouting.Validate([new("A","EGRESO","12","00",[]),new("B","EGRESO","13","00",[])]),"Dos predeterminadas se rechazan");
        reject(()=>ZeusRouting.Validate([new("A","OTRO","12","00",[1])]),"Movimiento desconocido se rechaza");
        reject(()=>ZeusRouting.Validate([new("Norte","EGRESO","12","00",[1]),new(" norte ","EGRESO","13","00",[2])]),"Sucursal no puede tener fuentes contradictorias para el mismo movimiento");
        reject(()=>ZeusRouting.Validate([new("A","EGRESO","1","XX",[1])]),"Validación de longitud y serie numérica");
        check(settings.FuentesAutomaticas is null&&configured.Fuente==settings.Fuente,"Resolver no altera configuración general ni otra empresa");
    }
}
