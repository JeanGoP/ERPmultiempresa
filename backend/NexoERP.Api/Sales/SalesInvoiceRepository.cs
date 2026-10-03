using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record SaleItem(long ArticuloId,long BodegaId,decimal Cantidad,decimal PrecioUnitarioConIva,long[]? UnidadesSerializadas);
public sealed record SaleAdvance(long ReciboCajaId,decimal Valor);
public sealed record SalesInvoiceInput(Guid OperacionGuid,string Numero,long ClienteId,long SucursalId,
    DateOnly FechaContable,DateOnly Vencimiento,SaleItem[] Lineas,decimal Financiacion,string? CuentaFinanciacion,
    int Cuotas,SaleAdvance[] Anticipos);

public sealed class SalesInvoiceRepository(TenantConnectionFactory connections)
{
    public async Task<object> ListAsync(long company,string? search,long? before,CancellationToken ct)
    {
        search=search?.Trim()??"";if(search.Length>100)throw new ArgumentException("Búsqueda demasiado larga.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT TOP(51) f.FacturaVentaId,f.Numero,f.FechaContable,t.RazonSocial,f.Total,f.AnticipoAplicado,f.SaldoPendiente,
                f.ZeusEstado,f.ZeusFuente,f.ZeusDocumento,f.ZeusError
            FROM ven.FacturaVenta f JOIN ter.Tercero t ON t.EmpresaId=f.EmpresaId AND t.TerceroId=f.ClienteId
            WHERE f.EmpresaId=@E AND (@Before IS NULL OR f.FacturaVentaId<@Before)
              AND (@Q='' OR f.Numero LIKE '%'+@Q+'%' OR t.RazonSocial LIKE '%'+@Q+'%'
                   OR t.NumeroIdentificacion LIKE '%'+@Q+'%' OR f.ZeusDocumento LIKE '%'+@Q+'%')
            ORDER BY f.FacturaVentaId DESC;
            """,company);
        q.Parameters.Add("@Q",SqlDbType.NVarChar,100).Value=search;
        q.Parameters.Add("@Before",SqlDbType.BigInt).Value=(object?)before??DBNull.Value;
        var list=new List<object>();long? next=null;await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))
        {
            if(list.Count==50)return new{items=list,siguiente=next};
            next=r.GetInt64(0);list.Add(new{id=next,numero=r.GetString(1),fecha=r.GetDateTime(2).ToString("yyyy-MM-dd"),cliente=r.GetString(3),total=r.GetDecimal(4),anticipo=r.GetDecimal(5),saldo=r.GetDecimal(6),zeusEstado=r.GetString(7),fuente=r.IsDBNull(8)?null:r.GetString(8),documento=r.IsDBNull(9)?null:r.GetString(9),error=r.IsDBNull(10)?null:r.GetString(10)});
        }
        return new{items=list,siguiente=(long?)null};
    }
    public async Task<object> OptionsAsync(long company,long? client,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT SucursalId,Codigo,Nombre FROM core.Sucursal WHERE EmpresaId=@E AND Activa=1 ORDER BY Codigo;
            SELECT t.TerceroId,t.NumeroIdentificacion,t.RazonSocial,p.ZeusEstado FROM ter.Tercero t
            JOIN ven.ClientePerfil p ON p.EmpresaId=t.EmpresaId AND p.TerceroId=t.TerceroId
            WHERE t.EmpresaId=@E AND t.Activo=1 ORDER BY t.RazonSocial;
            SELECT a.ArticuloId,a.Codigo,a.Descripcion,a.Tipo,a.ManejaInventario,a.ManejaSerial,a.PorcentajeIvaVenta,
                b.BodegaId,b.Codigo,b.Nombre,b.SucursalId,ISNULL(s.Existencia,0)
            FROM inv.Articulo a CROSS JOIN inv.Bodega b
            LEFT JOIN inv.SaldoArticuloBodega s ON s.EmpresaId=a.EmpresaId AND s.ArticuloId=a.ArticuloId AND s.BodegaId=b.BodegaId
            WHERE a.EmpresaId=@E AND b.EmpresaId=@E AND a.Activo=1 AND b.Activa=1 AND b.SucursalId IS NOT NULL
            ORDER BY b.Codigo,a.Codigo;
            SELECT u.UnidadSerializadaId,u.ArticuloId,u.BodegaActualId,u.Estado,ui.Tipo,ui.Valor
            FROM inv.UnidadSerializada u LEFT JOIN inv.UnidadIdentificador ui ON ui.EmpresaId=u.EmpresaId AND ui.UnidadSerializadaId=u.UnidadSerializadaId
            WHERE u.EmpresaId=@E AND u.Estado='DISPONIBLE' AND u.BodegaActualId IS NOT NULL;
            SELECT ReciboCajaId,Saldo FROM cxc.AnticipoCliente WHERE EmpresaId=@E AND ClienteId=@C AND Saldo>0 ORDER BY ReciboCajaId;
            """,company);
        q.Parameters.Add("@C",SqlDbType.BigInt).Value=(object?)client??DBNull.Value;
        var branches=new List<object>();var customers=new List<object>();var articles=new List<object>();var serials=new List<object>();var advances=new List<object>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))branches.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),nombre=r.GetString(2)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))customers.Add(new{id=r.GetInt64(0),identificacion=r.GetString(1),nombre=r.GetString(2),zeusEstado=r.GetString(3)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))articles.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),descripcion=r.GetString(2),tipo=r.GetString(3),inventario=r.GetBoolean(4),serial=r.GetBoolean(5),iva=r.IsDBNull(6)?(decimal?)null:r.GetDecimal(6),bodegaId=r.GetInt64(7),bodegaCodigo=r.GetString(8),bodega=r.GetString(9),sucursalId=r.GetInt64(10),existencia=r.GetDecimal(11)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))serials.Add(new{id=r.GetInt64(0),articuloId=r.GetInt64(1),bodegaId=r.GetInt64(2),estado=r.GetString(3),tipo=r.IsDBNull(4)?null:r.GetString(4),valor=r.IsDBNull(5)?null:r.GetString(5)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))advances.Add(new{id=r.GetInt64(0),saldo=r.GetDecimal(1)});
        return new{sucursales=branches,clientes=customers,articulos=articles,seriales=serials,anticipos=advances};
    }

    public async Task<object> PostAsync(long company,SalesInvoiceInput input,long user,CancellationToken ct)
    {
        if(input.OperacionGuid==Guid.Empty||input.ClienteId<=0||input.SucursalId<=0||input.FechaContable.Year<2000||input.Vencimiento<input.FechaContable)
            throw new ArgumentException("Selecciona cliente, sucursal, fecha y vencimiento válidos.");
        if(string.IsNullOrWhiteSpace(input.Numero)||input.Numero.Length>15||input.Numero.Any(char.IsControl))
            throw new ArgumentException("Escribe el número de la factura (máximo 15 caracteres admitidos por Zeus).");
        if(input.Lineas is null||input.Lineas.Length is <1 or >100||input.Cuotas is <1 or >120)
            throw new ArgumentException("La factura requiere entre 1 y 100 líneas y entre 1 y 120 cuotas.");
        if(input.Financiacion<0||decimal.Round(input.Financiacion,2)!=input.Financiacion)
            throw new ArgumentException("El valor de financiación debe tener máximo dos decimales.");
        if(input.Financiacion>0&&(string.IsNullOrWhiteSpace(input.CuentaFinanciacion)||!input.CuentaFinanciacion.StartsWith("4135",StringComparison.Ordinal)))
            throw new ArgumentException("Selecciona la cuenta de ingreso 4135 de financiación en Zeus.");
        var advances=input.Anticipos??[];
        if(advances.Length>100||advances.Any(x=>x.ReciboCajaId<=0||x.Valor<=0||decimal.Round(x.Valor,2)!=x.Valor)
            ||advances.GroupBy(x=>x.ReciboCajaId).Any(g=>g.Count()>1))throw new ArgumentException("Revisa los anticipos seleccionados.");
        foreach(var line in input.Lineas)
            if(line.ArticuloId<=0||line.BodegaId<=0||line.Cantidad<=0||decimal.Round(line.Cantidad,6)!=line.Cantidad
                ||line.PrecioUnitarioConIva<=0||decimal.Round(line.PrecioUnitarioConIva,2)!=line.PrecioUnitarioConIva)
                throw new ArgumentException("Revisa artículo, bodega, cantidad y precio unitario con IVA incluido.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT FacturaVentaId,Contenido FROM ven.FacturaVenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND OperacionGuid=@Key",company,tx);
        ZeusRepository.Add(q,"@Key",input.OperacionGuid);
        await using(var prior=await q.ExecuteReaderAsync(ct))
            if(await prior.ReadAsync(ct))
            {
                if(prior.GetString(1)!=JsonSerializer.Serialize(input))throw new ArgumentException("La clave de operación ya corresponde a otra factura. Actualiza y vuelve a intentarlo.");
                var priorId=prior.GetInt64(0);await prior.CloseAsync();await tx.CommitAsync(ct);
                return new{id=priorId,estado="CONTABILIZADO",repetido=true};
            }
        ZeusRepository.Add(q,"@B",input.SucursalId);ZeusRepository.Add(q,"@C",input.ClienteId);ZeusRepository.Add(q,"@Date",input.FechaContable.ToDateTime(TimeOnly.MinValue));
        q.CommandText="SELECT PeriodoInventarioId FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Estado IN('ABIERTO','REABIERTO') AND @Date BETWEEN FechaInicio AND FechaFin";
        var period=await q.ExecuteScalarAsync(ct);
        if(period is null)throw new ArgumentException("Abre el período de la fecha contable antes de facturar.");
        q.CommandText="SELECT Nombre FROM core.Sucursal WHERE EmpresaId=@E AND SucursalId=@B AND Activa=1";
        var branch=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Selecciona una sucursal activa.");
        q.CommandText="SELECT p.ZeusEstado,t.NumeroIdentificacion,t.RazonSocial FROM ter.Tercero t JOIN ven.ClientePerfil p ON p.EmpresaId=t.EmpresaId AND p.TerceroId=t.TerceroId WHERE t.EmpresaId=@E AND t.TerceroId=@C AND t.Activo=1";
        string customerState,identification,customerName;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("Selecciona un cliente activo.");
            customerState=r.GetString(0);identification=r.GetString(1);customerName=r.GetString(2);
        }
        if(customerState is not("TERCERO" or "CLIENTE"))throw new ArgumentException("El tercero del cliente debe estar confirmado en Zeus antes de emitir la primera factura.");
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WHERE EmpresaId=@E";
        var settings=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Configura Zeus para esta empresa."))!;
        if(!settings.Habilitado||(settings.FuentesAutomaticas??[]).All(x=>x.Movimiento!="FACTURACION"||x.SucursalId!=input.SucursalId))
            throw new ArgumentException("Configura y habilita la fuente FACTURACION de esta sucursal en Zeus.");
        settings=ZeusRouting.Resolve(settings,input.SucursalId,"FACTURACION",branch);
        var validated=new List<(SaleItem Input,decimal Base,decimal Iva,decimal Tarifa,bool Inventory,bool Serial,ZeusWarehouseAccounts Accounts)>();
        foreach(var line in input.Lineas)
        {
            q.Parameters.Add("@Article",SqlDbType.BigInt).Value=line.ArticuloId;
            q.Parameters.Add("@Warehouse",SqlDbType.BigInt).Value=line.BodegaId;
            q.CommandText="""
                SELECT a.PorcentajeIvaVenta,a.ManejaInventario,a.ManejaSerial,ISNULL(s.Existencia,0),z.Configuracion,z.Servidor,z.BaseDatos
                FROM inv.Articulo a JOIN inv.Bodega b ON b.EmpresaId=a.EmpresaId AND b.BodegaId=@Warehouse AND b.SucursalId=@B AND b.Activa=1
                LEFT JOIN inv.SaldoArticuloBodega s WITH(UPDLOCK,HOLDLOCK) ON s.EmpresaId=a.EmpresaId AND s.BodegaId=@Warehouse AND s.ArticuloId=a.ArticuloId
                LEFT JOIN core.ZeusBodegaCuenta z ON z.EmpresaId=a.EmpresaId AND z.BodegaId=@Warehouse
                WHERE a.EmpresaId=@E AND a.ArticuloId=@Article AND a.Activo=1;
                """;
            decimal rate,stock;bool inventory,serial;string? accountsJson,server,db;
            await using(var r=await q.ExecuteReaderAsync(ct))
            {
                if(!await r.ReadAsync(ct)||r.IsDBNull(0))throw new ArgumentException("El artículo no existe, no pertenece a la sucursal o no tiene IVA de venta clasificado.");
                rate=r.GetDecimal(0);inventory=r.GetBoolean(1);serial=r.GetBoolean(2);stock=r.GetDecimal(3);
                accountsJson=r.IsDBNull(4)?null:r.GetString(4);server=r.IsDBNull(5)?null:r.GetString(5);db=r.IsDBNull(6)?null:r.GetString(6);
            }
            q.Parameters.RemoveAt("@Article");q.Parameters.RemoveAt("@Warehouse");
            if(inventory&&stock<line.Cantidad)throw new ArgumentException("No hay existencias suficientes en la bodega seleccionada.");
            if(serial&&(line.UnidadesSerializadas?.Length!=line.Cantidad||line.UnidadesSerializadas.Distinct().Count()!=line.UnidadesSerializadas.Length))
                throw new ArgumentException("Selecciona una unidad serializada distinta por cada artículo vendido.");
            if(!serial&&(line.UnidadesSerializadas?.Length??0)>0)throw new ArgumentException("Este artículo no maneja seriales.");
            if(accountsJson is null||server!=settings.ServidorEsperado||db!=settings.BaseEsperada)
                throw new ArgumentException("Configura las cuentas de venta de esta bodega para el destino Zeus actual.");
            var accounts=JsonSerializer.Deserialize<ZeusWarehouseAccounts>(accountsJson)!;
            if(string.IsNullOrWhiteSpace(accounts.CarteraClientes))throw new ArgumentException("Configura la cuenta 13 de clientes en la bodega.");
            var gross=decimal.Round(line.Cantidad*line.PrecioUnitarioConIva,2,MidpointRounding.AwayFromZero);
            var baseValue=decimal.Round(gross/(1+rate/100),2,MidpointRounding.AwayFromZero);
            validated.Add((line,baseValue,gross-baseValue,rate,inventory,serial,accounts));
        }
        if(validated.Select(x=>x.Accounts.CarteraClientes).Distinct().Count()>1)
            throw new ArgumentException("Las bodegas de la factura deben usar la misma cuenta de cartera del cliente.");
        var total=validated.Sum(x=>x.Base+x.Iva)+input.Financiacion;
        var advanceTotal=advances.Sum(x=>x.Valor);
        if(advanceTotal>total)throw new ArgumentException("El anticipo no puede superar el total de la factura.");
        foreach(var advance in advances.OrderBy(x=>x.ReciboCajaId))
        {
            q.Parameters.Add("@Receipt",SqlDbType.BigInt).Value=advance.ReciboCajaId;
            q.CommandText="SELECT a.Saldo,r.ZeusEstado FROM cxc.AnticipoCliente a WITH(UPDLOCK,HOLDLOCK) JOIN cxc.ReciboCaja r ON r.EmpresaId=a.EmpresaId AND r.ReciboCajaId=a.ReciboCajaId WHERE a.EmpresaId=@E AND a.ReciboCajaId=@Receipt AND a.ClienteId=@C";
            await using(var r=await q.ExecuteReaderAsync(ct))
                if(!await r.ReadAsync(ct)||r.GetDecimal(0)<advance.Valor||r.GetString(1)!="CONTABILIZADO")
                    throw new ArgumentException("El anticipo no pertenece al cliente, no tiene saldo o no está confirmado en Zeus.");
            q.Parameters.RemoveAt("@Receipt");
        }
        ZeusRepository.Add(q,"@N",input.Numero.Trim());ZeusRepository.Add(q,"@Due",input.Vencimiento.ToDateTime(TimeOnly.MinValue));
        ZeusRepository.Add(q,"@Base",validated.Sum(x=>x.Base));ZeusRepository.Add(q,"@Iva",validated.Sum(x=>x.Iva));
        ZeusRepository.Add(q,"@Finance",input.Financiacion);ZeusRepository.Add(q,"@Total",total);ZeusRepository.Add(q,"@Advance",advanceTotal);
        ZeusRepository.Add(q,"@Balance",total-advanceTotal);ZeusRepository.Add(q,"@Terms",input.Cuotas);
        ZeusRepository.Add(q,"@Json",JsonSerializer.Serialize(input));ZeusRepository.Add(q,"@User",user);
        q.CommandText="INSERT ven.FacturaVenta(EmpresaId,OperacionGuid,Numero,SucursalId,ClienteId,FechaContable,Vencimiento,Base,Iva,Financiacion,Total,AnticipoAplicado,SaldoPendiente,Cuotas,Contenido,CreadoPor) OUTPUT inserted.FacturaVentaId VALUES(@E,@Key,@N,@B,@C,@Date,@Due,@Base,@Iva,@Finance,@Total,@Advance,@Balance,@Terms,@Json,@User)";
        var id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));ZeusRepository.Add(q,"@Id",id);
        foreach(var advance in advances)
        {
            q.Parameters.Add("@Receipt",SqlDbType.BigInt).Value=advance.ReciboCajaId;
            q.Parameters.Add("@Value",SqlDbType.Decimal).Value=advance.Valor;
            q.CommandText="UPDATE cxc.AnticipoCliente SET Saldo=Saldo-@Value WHERE EmpresaId=@E AND ReciboCajaId=@Receipt AND ClienteId=@C AND Saldo>=@Value; IF @@ROWCOUNT<>1 THROW 52311,'El anticipo cambió; no se emitió la factura.',1; INSERT ven.FacturaAnticipo(EmpresaId,FacturaVentaId,ReciboCajaId,Valor) VALUES(@E,@Id,@Receipt,@Value)";
            await q.ExecuteNonQueryAsync(ct);q.Parameters.RemoveAt("@Receipt");q.Parameters.RemoveAt("@Value");
        }
        var lineNumber=0;
        var movements=new List<ZeusMovement>{new(new ZeusAccount("CLIENTE",validated[0].Accounts.CarteraClientes!),total)};
        foreach(var item in validated)
        {
            lineNumber++;
            await using var line=ZeusRepository.Command(c,"INSERT ven.FacturaVentaLinea(EmpresaId,FacturaVentaId,ArticuloId,BodegaId,Cantidad,PrecioConIva,TarifaIva,Base,Iva,UnidadesJson) OUTPUT inserted.FacturaVentaLineaId VALUES(@E,@Invoice,@Article,@Warehouse,@Qty,@Price,@Rate,@Base,@Iva,@Serials)",company,tx);
            foreach(var p in new (string,object)[]{("@Invoice",id),("@Article",item.Input.ArticuloId),("@Warehouse",item.Input.BodegaId),("@Qty",item.Input.Cantidad),("@Price",item.Input.PrecioUnitarioConIva),("@Rate",item.Tarifa),("@Base",item.Base),("@Iva",item.Iva)})ZeusRepository.Add(line,p.Item1,p.Item2);
            line.Parameters.Add("@Serials",SqlDbType.NVarChar,-1).Value=item.Serial?JsonSerializer.Serialize(item.Input.UnidadesSerializadas):DBNull.Value;
            var lineId=Convert.ToInt64(await line.ExecuteScalarAsync(ct));
            movements.Add(new(new ZeusAccount("INGRESO",item.Accounts.Ingreso),-item.Base));
            if(item.Iva>0)movements.Add(new(new ZeusAccount("IVA_VENTA",item.Accounts.IvaVentas),-item.Iva,item.Base,item.Tarifa));
            if(!item.Inventory)continue;
            await using var move=c.CreateCommand();move.Transaction=tx;move.CommandType=CommandType.StoredProcedure;
            move.CommandText=item.Serial?"inv.usp_ContabilizarSalidaSerializada":"inv.usp_ContabilizarSalida";
            void Add(string name,object value)=>move.Parameters.AddWithValue(name,value);
            Add("@EmpresaId",company);Add("@BodegaId",item.Input.BodegaId);Add("@ArticuloId",item.Input.ArticuloId);
            Add("@PeriodoInventarioId",Convert.ToInt64(period));Add("@FechaMovimiento",input.FechaContable.ToDateTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(12))));
            Add("@FechaContable",input.FechaContable.ToDateTime(TimeOnly.MinValue));Add("@TipoMovimiento","VENTA");
            Add("@ModuloOrigen","VENTAS");Add("@TipoDocumentoOrigen","FACTURA_VENTA");Add("@DocumentoOrigenId",id);
            Add("@DocumentoLineaOrigenId",lineId);Add("@NumeroDocumento",input.Numero.Trim());Add("@TerceroId",input.ClienteId);
            Add("@CantidadSalida",item.Input.Cantidad);var moveKey=Guid.NewGuid();Add("@IdempotencyKey",moveKey);Add("@UsuarioId",user);
            if(item.Serial)Add("@UnidadesJson",JsonSerializer.Serialize(item.Input.UnidadesSerializadas));
            await using(var reader=await move.ExecuteReaderAsync(ct))do{while(await reader.ReadAsync(ct)){}}while(await reader.NextResultAsync(ct));
            await using var cost=ZeusRepository.Command(c,"SELECT ABS(ValorMovimiento) FROM inv.MovimientoInventario WHERE EmpresaId=@E AND IdempotencyKey=@Move",company,tx);
            ZeusRepository.Add(cost,"@Move",moveKey);var value=await cost.ExecuteScalarAsync(ct);
            if(value is null)throw new InvalidOperationException("La salida de inventario no confirmó su costo.");
            await using var update=ZeusRepository.Command(c,"UPDATE ven.FacturaVentaLinea SET Costo=@Cost WHERE EmpresaId=@E AND FacturaVentaLineaId=@Line",company,tx);
            var costValue=decimal.Round(Convert.ToDecimal(value),2,MidpointRounding.AwayFromZero);
            ZeusRepository.Add(update,"@Cost",costValue);ZeusRepository.Add(update,"@Line",lineId);await update.ExecuteNonQueryAsync(ct);
            if(costValue>0)
            {
                movements.Add(new(new ZeusAccount("COSTO_VENTA",item.Accounts.CostoVenta),costValue));
                movements.Add(new(new ZeusAccount("INVENTARIO",item.Accounts.Inventario),-costValue));
            }
        }
        if(input.Financiacion>0)movements.Add(new(new ZeusAccount("FINANCIACION",input.CuentaFinanciacion!.Trim()),-input.Financiacion));
        if(advanceTotal>0)
        {
            var advanceAccount=ZeusJournal.GeneralAdvanceAccount(settings)?.Cuenta
                ??throw new ArgumentException("Configura la cuenta general de anticipos antes de aplicarlos en factura.");
            movements.Add(new(new ZeusAccount("ANTICIPO",advanceAccount),advanceTotal));
            movements.Add(new(new ZeusAccount("CLIENTE",validated[0].Accounts.CarteraClientes!),-advanceTotal));
        }
        if(movements.Sum(x=>x.Valor)!=0)throw new InvalidOperationException("La factura no quedó balanceada. No se contabilizó.");
        var source=new ZeusSource(0,input.ClienteId,input.Numero.Trim(),input.FechaContable.ToDateTime(TimeOnly.MinValue),input.FechaContable.ToDateTime(TimeOnly.MinValue),input.Vencimiento.ToDateTime(TimeOnly.MinValue),total,validated.Sum(x=>x.Iva),0,[],ProveedorNombre:customerName);
        var snapshot=new ZeusSnapshot(settings,source,new(input.ClienteId,identification,identification),movements.ToArray(),
            ClienteDocumento:new("FACTURA","FACTURA DE VENTA",validated[0].Accounts.CarteraClientes!));
        q.CommandText="UPDATE ven.FacturaVenta SET Snapshot=@Snapshot WHERE EmpresaId=@E AND FacturaVentaId=@Id";
        ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(snapshot));await q.ExecuteNonQueryAsync(ct);
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'CONTABILIZAR_FACTURA_VENTA','ven.FacturaVenta',CONVERT(varchar(30),@Id),@Json,'ERP')";
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
        return new{id,numero=input.Numero,estado="CONTABILIZADO",zeusEstado="PENDIENTE",total,saldo=total-advanceTotal,repetido=false};
    }
}
