using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Security;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Treasury;

public interface IDisbursementCheck
{
    Task CheckDisbursementAsync(long company,ZeusSnapshot snapshot,CancellationToken ct);
}
public sealed record CashAccount(long SucursalId,string MedioPago,string Cuenta,string MonedaZeus,int Version=0);
public sealed class DisbursementPosting(TenantConnectionFactory connections,IDisbursementCheck check)
{
    public const string Permission="TESORERIA.EGRESO.CONTABILIZAR";
    public async Task<object> PostAsync(long company,DisbursementDraft input,long user,CancellationToken ct)
    {
        input=DisbursementRepository.Validate(input);
        if(input.Version!=0||input.Moneda!="COP"||input.BancoCaja!=""||input.CuentaSalida!="")
            throw new ArgumentException("El egreso usa COP y las cuentas configuradas por sucursal; no admite cuentas de salida digitadas ni edición.");
        if(input.Referencia.Length>20)throw new ArgumentException("La referencia bancaria admite máximo 20 caracteres.");
        var json=JsonSerializer.Serialize(input);var hash=SHA256.HashData(Encoding.UTF8.GetBytes(json));
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT EgresoId,Huella FROM cxp.Egreso WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND OperacionGuid=@Key",company,tx);
        ZeusRepository.Add(q,"@Key",input.OperacionGuid);
        long? existing=null;
        await using(var r=await q.ExecuteReaderAsync(ct))if(await r.ReadAsync(ct))
        {
            if(!((byte[])r[1]).SequenceEqual(hash))throw new DraftConflict("La operación ya fue contabilizada con otros datos. No se ha creado otro pago.");
            existing=r.GetInt64(0);
        }
        if(existing is not null){await tx.CommitAsync(ct);return new{id=existing,estado="CONTABILIZADO",repetido=true};}
        ZeusRepository.Add(q,"@B",input.SucursalId);ZeusRepository.Add(q,"@T",input.TerceroId);
        ZeusRepository.Add(q,"@Date",input.FechaContable.ToDateTime(TimeOnly.MinValue));
        q.CommandText="SELECT COUNT(*) FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Estado IN('ABIERTO','REABIERTO') AND @Date BETWEEN FechaInicio AND FechaFin";
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new ArgumentException("Abre el período de la fecha contable antes de contabilizar el egreso.");
        q.CommandText="SELECT Nombre FROM core.Sucursal WHERE EmpresaId=@E AND SucursalId=@B AND Activa=1";
        var branch=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Sucursal inexistente o inactiva.");
        q.CommandText="SELECT RazonSocial FROM ter.Tercero WHERE EmpresaId=@E AND TerceroId=@T AND Activo=1";
        var name=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Beneficiario inexistente o inactivo.");
        q.CommandText="SELECT NumeroIdentificacion FROM ter.Tercero WHERE EmpresaId=@E AND TerceroId=@T";
        var identification=(string)(await q.ExecuteScalarAsync(ct))!;
        if(identification.Length is <1 or >10||identification.Any(c=>!char.IsAsciiLetterOrDigit(c)))throw new ArgumentException("La identificación Zeus admite máximo 10 caracteres sin separadores.");
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WITH(HOLDLOCK) WHERE EmpresaId=@E";
        var settings=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Configura Zeus para esta empresa."))!;
        if(!settings.Habilitado)throw new ArgumentException("Habilita la integración Zeus de esta empresa antes de contabilizar egresos.");
        if(!(settings.FuentesAutomaticas??[]).Any(r=>r.Movimiento=="EGRESO"&&(r.SucursalId==input.SucursalId||r.SucursalId is null&&r.Sucursal==branch)))
            throw new ArgumentException("Configura la fuente EGRESO de esta sucursal en Integración Zeus; no se usa la fuente de compras.");
        settings=ZeusRouting.Resolve(settings,input.SucursalId,"EGRESO",branch);
        var supplier=settings.Proveedores.SingleOrDefault(p=>p.ProveedorId==input.TerceroId)
            ??new ZeusSupplier(input.TerceroId,identification,identification);
        ZeusRepository.Add(q,"@Method",input.MedioPago);
        q.CommandText="SELECT Cuenta,Banco,Servidor,BaseDatos,MonedaZeus FROM cxp.EgresoCuentaSucursal WITH(HOLDLOCK) WHERE EmpresaId=@E AND SucursalId=@B AND MedioPago=@Method";
        string account,bank,paymentCurrency;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("Configura la cuenta de caja/banco para esta sucursal y medio de pago.");
            account=r.GetString(0);bank=r.GetString(1);
            paymentCurrency=r.GetString(4);
            if(r.GetString(2)!=settings.ServidorEsperado||r.GetString(3)!=settings.BaseEsperada)throw new ArgumentException("La cuenta de salida pertenece a otro destino Zeus. Configúrala nuevamente.");
        }
        var invoices=new List<ZeusPaymentInvoice>();var movements=new List<ZeusMovement>();
        foreach(var line in input.Lineas.OrderBy(l=>l.DocumentoPorPagarId))
        {
            if(line.Tipo=="GASTO")
            {
                if(string.IsNullOrWhiteSpace(line.Cuenta)||line.Cuenta.Length>16)throw new ArgumentException("Selecciona la cuenta de detalle del gasto.");
                movements.Add(new(new ZeusAccount("GASTO",line.Cuenta),line.Valor));continue;
            }
            if(!q.Parameters.Contains("@P"))q.Parameters.Add("@P",SqlDbType.BigInt);
            q.Parameters["@P"].Value=line.DocumentoPorPagarId!;
            q.CommandText="""
                SELECT p.SaldoPendiente,p.FechaReconocimiento,p.Moneda,p.TerceroId,p.Estado,p.FechaVencimiento,
                    z.Snapshot,z.Estado
                FROM cxp.DocumentoPorPagar p WITH(UPDLOCK,HOLDLOCK)
                OUTER APPLY(SELECT TOP(1) z.Snapshot,z.Estado FROM inv.RecepcionMercancia r JOIN core.ZeusEnvio z ON z.EmpresaId=r.EmpresaId AND z.RecepcionMercanciaId=r.RecepcionMercanciaId
                    WHERE r.EmpresaId=p.EmpresaId AND r.DocumentoProveedorId=p.DocumentoProveedorId ORDER BY z.ZeusEnvioId DESC) z
                WHERE p.EmpresaId=@E AND p.DocumentoPorPagarId=@P;
                """;
            await using var r=await q.ExecuteReaderAsync(ct);
            if(!await r.ReadAsync(ct)||r.GetInt64(3)!=input.TerceroId||r.GetString(2).Trim()!=input.Moneda||r.GetString(4) is not("ABIERTA" or "PARCIAL")||r.GetDecimal(0)<line.Valor||DateOnly.FromDateTime(r.GetDateTime(1))>input.FechaContable)
                throw new ArgumentException("Una factura no corresponde al proveedor/moneda, no tiene saldo suficiente o su reconocimiento es posterior al pago. Actualiza las facturas.");
            if(r.IsDBNull(6)||r.IsDBNull(7)||r.GetString(7)!="CONTABILIZADO")throw new ArgumentException("La factura debe estar contabilizada en Zeus antes de aplicar su pago. Revisa el seguimiento de su entrada.");
            var original=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(6))!;
            if(original.Configuracion.ServidorEsperado!=settings.ServidorEsperado||original.Configuracion.BaseEsperada!=settings.BaseEsperada||original.Proveedor!=supplier)
                throw new ArgumentException("La obligación fue contabilizada en otro destino o con otro proveedor Zeus. Requiere conciliación antes del pago.");
            var liability=original.Movimientos.Where(m=>m.Regla.Concepto=="PROVEEDOR").Select(m=>m.Regla.Cuenta).Distinct().Single();
            invoices.Add(new(line.DocumentoPorPagarId!.Value,liability,original.Configuracion.TipoFactura,original.Origen.Factura,"",original.Configuracion.UnidadNegocio,r.GetDateTime(5),line.Valor));
            movements.Add(new(new ZeusAccount("PROVEEDOR",liability),line.Valor));
        }
        if(invoices.GroupBy(i=>(i.Cuenta,i.Tipo,i.Numero,i.Referencia,i.UnidadNegocio)).Any(g=>g.Count()>1))throw new ArgumentException("Dos obligaciones comparten la misma identificación de factura en Zeus. Concilia antes de pagar.");
        var total=input.Lineas.Sum(l=>l.Valor);movements.Add(new(new ZeusAccount("BANCO_CAJA",account),-total));
        var date=input.FechaContable.ToDateTime(TimeOnly.MinValue);
        var snapshot=new ZeusSnapshot(settings,new(0,input.TerceroId,"EGRESO",date,date,date,total,0,0,[],ProveedorNombre:name),supplier,movements.ToArray(),new(input.Concepto,bank,account,input.Referencia,invoices.ToArray(),paymentCurrency));
        // Validación remota de solo lectura ANTES de afectar el ERP. Nunca se envía aquí a Zeus.
        await check.CheckDisbursementAsync(company,snapshot,ct);
        ZeusRepository.Add(q,"@J",json);ZeusRepository.Add(q,"@Hash",hash);ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(snapshot));ZeusRepository.Add(q,"@U",user);ZeusRepository.Add(q,"@Total",total);ZeusRepository.Add(q,"@Currency",input.Moneda);
        q.CommandText="INSERT cxp.Egreso(EmpresaId,OperacionGuid,SucursalId,TerceroId,FechaContable,Moneda,Total,Contenido,Huella,Snapshot,CreadoPor) OUTPUT inserted.EgresoId VALUES(@E,@Key,@B,@T,@Date,@Currency,@Total,@J,@Hash,@Snapshot,@U)";
        var id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));ZeusRepository.Add(q,"@Id",id);
        foreach(var line in input.Lineas)
        {
            var ledgerAccount=line.Tipo=="FACTURA"?invoices.Single(i=>i.DocumentoPorPagarId==line.DocumentoPorPagarId).Cuenta:line.Cuenta;
            await using var insert=ZeusRepository.Command(c,"INSERT cxp.EgresoLinea(EmpresaId,EgresoId,DocumentoPorPagarId,Cuenta,Concepto,Debito) OUTPUT inserted.EgresoLineaId VALUES(@E,@Id,@P,@Account,@Concept,@Value)",company,tx);
            ZeusRepository.Add(insert,"@Id",id);insert.Parameters.Add("@P",SqlDbType.BigInt).Value=(object?)line.DocumentoPorPagarId??DBNull.Value;
            ZeusRepository.Add(insert,"@Account",ledgerAccount);ZeusRepository.Add(insert,"@Concept",line.Concepto);ZeusRepository.Add(insert,"@Value",line.Valor);
            var lineId=Convert.ToInt64(await insert.ExecuteScalarAsync(ct));
            if(line.Tipo!="FACTURA")continue;
            ZeusRepository.Add(insert,"@Line",lineId);ZeusRepository.Add(insert,"@T",input.TerceroId);ZeusRepository.Add(insert,"@Date",date);ZeusRepository.Add(insert,"@Currency",input.Moneda);
            insert.CommandText="""
                UPDATE cxp.DocumentoPorPagar SET SaldoPendiente=SaldoPendiente-@Value,Estado=CASE WHEN SaldoPendiente=@Value THEN 'PAGADA' ELSE 'PARCIAL' END,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND DocumentoPorPagarId=@P AND SaldoPendiente>=@Value;
                IF @@ROWCOUNT<>1 THROW 52112,'El saldo cambió; no se contabilizó el egreso.',1;
                INSERT cxp.MovimientoProveedor(EmpresaId,TerceroId,DocumentoPorPagarId,TipoMovimiento,FechaMovimiento,NumeroDocumento,Moneda,Cargo,Abono,TipoDocumentoOrigen,DocumentoOrigenId)
                VALUES(@E,@T,@P,'PAGO',@Date,CONCAT('CE-',@Id),@Currency,0,@Value,'EGRESO_LINEA',@Line);
                """;
            await insert.ExecuteNonQueryAsync(ct);
        }
        q.CommandText="""
            INSERT cxp.EgresoLinea(EmpresaId,EgresoId,Cuenta,Concepto,Credito) VALUES(@E,@Id,@Account,N'Salida de caja/banco',@Total);
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@U,'CONTABILIZAR_EGRESO','cxp.Egreso',CONVERT(varchar(30),@Id),@J,'ERP');
            """;
        ZeusRepository.Add(q,"@Account",account);await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
        return new{id,estado="CONTABILIZADO",zeusEstado="PENDIENTE",repetido=false};
    }

    public async Task<object> ListAsync(long company,long? before,CancellationToken ct,string? search=null)
    {
        search=search?.Trim()??"";
        if(search.Length>120)throw new ArgumentException("La búsqueda admite hasta 120 caracteres.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT TOP(51) e.EgresoId,e.FechaContable,t.RazonSocial,e.Moneda,e.Total,e.ZeusEstado,e.ZeusFuente,e.ZeusDocumento,e.ZeusError FROM cxp.Egreso e JOIN ter.Tercero t ON t.EmpresaId=e.EmpresaId AND t.TerceroId=e.TerceroId WHERE e.EmpresaId=@E AND (@Before IS NULL OR e.EgresoId<@Before) AND (@Search='' OR CHARINDEX(@Search,t.RazonSocial)>0 OR CHARINDEX(@Search,t.NumeroIdentificacion)>0 OR CONCAT('CE-',e.EgresoId)=@Search OR CONVERT(varchar(20),e.EgresoId)=@Search OR CHARINDEX(@Search,e.ZeusDocumento)>0) ORDER BY e.EgresoId DESC",company);
        q.Parameters.Add("@Search",SqlDbType.NVarChar,120).Value=search;
        q.Parameters.Add("@Before",SqlDbType.BigInt).Value=(object?)before??DBNull.Value;var rows=new List<object>();long? next=null;
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct)){if(rows.Count==50)return new{items=rows,siguiente=next};next=r.GetInt64(0);rows.Add(new{id=next,fecha=r.GetDateTime(1).ToString("yyyy-MM-dd"),beneficiario=r.GetString(2),moneda=r.GetString(3),total=r.GetDecimal(4),estado="CONTABILIZADO",zeusEstado=r.GetString(5),fuente=r.IsDBNull(6)?null:r.GetString(6),documento=r.IsDBNull(7)?null:r.GetString(7),error=r.IsDBNull(8)?null:r.GetString(8)});}
        return new{items=rows,siguiente=(long?)null};
    }
    public async Task<object?> GetAsync(long company,long id,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);await using var q=ZeusRepository.Command(c,"SELECT Contenido,Snapshot FROM cxp.Egreso WHERE EmpresaId=@E AND EgresoId=@Id",company);ZeusRepository.Add(q,"@Id",id);
        await using var r=await q.ExecuteReaderAsync(ct);return await r.ReadAsync(ct)?new{id,estado="CONTABILIZADO",datos=JsonSerializer.Deserialize<DisbursementDraft>(r.GetString(0)),asiento=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(1))}:null;
    }
    public async Task<object> AccountsAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);await using var q=ZeusRepository.Command(c,"SELECT SucursalId,MedioPago,Cuenta,Nombre,Version,MonedaZeus FROM cxp.EgresoCuentaSucursal WHERE EmpresaId=@E",company);
        await using var r=await q.ExecuteReaderAsync(ct);var list=new List<object>();while(await r.ReadAsync(ct))list.Add(new{sucursalId=r.GetInt64(0),medioPago=r.GetString(1),cuenta=r.GetString(2),nombre=r.GetString(3),version=r.GetInt32(4),monedaZeus=r.GetString(5)});return list;
    }
    public async Task SaveAccountAsync(long company,CashAccount input,long user,ZeusSettings settings,ZeusCashAccount account,CancellationToken ct)
    {
        if(input.MedioPago is not("EFECTIVO" or "TRANSFERENCIA" or "CHEQUE")||input.SucursalId<=0)throw new ArgumentException("Sucursal o medio de pago inválido.");
        if(input.MedioPago!="EFECTIVO"&&account.Banco.Length==0)throw new ArgumentException("La cuenta bancaria debe tener banco asociado en Zeus.");
        if(input.MedioPago=="EFECTIVO"&&account.Banco.Length>0)throw new ArgumentException("Selecciona una cuenta de caja, no una cuenta bancaria.");
        await using var c=await connections.OpenAsync(company,false,ct);await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"""
            IF NOT EXISTS(SELECT 1 FROM core.Sucursal WHERE EmpresaId=@E AND SucursalId=@B AND Activa=1) THROW 52113,'Sucursal no válida.',1;
            IF ISNULL((SELECT Version FROM cxp.EgresoCuentaSucursal WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND SucursalId=@B AND MedioPago=@Method),0)<>@V THROW 52113,'La configuración cambió; actualiza.',1;
            IF @V=0 INSERT cxp.EgresoCuentaSucursal(EmpresaId,SucursalId,MedioPago,Cuenta,Nombre,Banco,MonedaZeus,Servidor,BaseDatos,ActualizadoPor) VALUES(@E,@B,@Method,@Account,@Name,@Bank,@Money,@Server,@Db,@U);
            ELSE UPDATE cxp.EgresoCuentaSucursal SET Cuenta=@Account,Nombre=@Name,Banco=@Bank,MonedaZeus=@Money,Servidor=@Server,BaseDatos=@Db,Version=Version+1,ActualizadoPor=@U WHERE EmpresaId=@E AND SucursalId=@B AND MedioPago=@Method;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@U,'CONFIGURAR_CUENTA_EGRESO','cxp.EgresoCuentaSucursal',CONCAT(@B,':',@Method),@Json,'ERP');
            """,company,tx);
        foreach(var p in new (string,object)[]{("@B",input.SucursalId),("@Method",input.MedioPago),("@Account",account.Codigo),("@Name",account.Nombre),("@Bank",account.Banco),("@Server",settings.ServidorEsperado),("@Db",settings.BaseEsperada),("@U",user),("@V",input.Version),("@Json",JsonSerializer.Serialize(input))})ZeusRepository.Add(q,p.Item1,p.Item2);
        ZeusRepository.Add(q,"@Money",input.MonedaZeus);await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
    }
}

public static class PostedDisbursementsModule
{
    public static void MapPostedDisbursements(this WebApplication app)
    {
        var g=app.MapGroup("/api/v1/companies/{empresaId:long}/disbursements");
        g.MapPost("/{id:long}/retry",async(long empresaId,long id,HttpContext http,DisbursementQueue queue,CancellationToken ct)=>{await queue.RetryAsync(empresaId,id,Convert.ToInt64(http.Items["UsuarioId"]),ct);return Results.NoContent();}).RequireErpPermission(DisbursementPosting.Permission);
        g.MapPost("/{id:long}/reconcile",async(long empresaId,long id,DisbursementQueue queue,ZeusTransport transport,CancellationToken ct)=>Results.Ok(await queue.ReconcileAsync(empresaId,id,transport,ct))).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        g.AddEndpointFilter(async(ctx,next)=>{try{return await next(ctx);}catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}catch(DraftConflict e){return Results.Conflict(new{error=e.Message});}catch(SqlException e)when(e.Number is 52112 or 52113 or 52114){return Results.Conflict(new{error=e.Message});}catch(SqlException){return Results.Json(new{error="No se pudo completar la operación. Comprueba conexión, permisos, período y configuración. No repitas un pago sin actualizar su estado."},statusCode:502);}});
        g.MapGet("",async(long empresaId,long? antes,string? q,DisbursementPosting repo,CancellationToken ct)=>Results.Ok(await repo.ListAsync(empresaId,antes,ct,q))).RequireErpPermission(DisbursementPosting.Permission);
        g.MapGet("/options",async(long empresaId,string? q,long? terceroId,DisbursementRepository repo,CancellationToken ct)=>Results.Ok(await repo.OptionsAsync(empresaId,q,terceroId,ct))).RequireErpPermission(DisbursementPosting.Permission);
        g.MapGet("/{id:long}",async(long empresaId,long id,DisbursementPosting repo,CancellationToken ct)=>{var result=await repo.GetAsync(empresaId,id,ct);return result is null?Results.NotFound():Results.Ok(result);}).RequireErpPermission(DisbursementPosting.Permission);
        g.MapPost("",async(long empresaId,DisbursementDraft input,HttpContext http,DisbursementPosting repo,CancellationToken ct)=>Results.Ok(await repo.PostAsync(empresaId,input,Convert.ToInt64(http.Items["UsuarioId"]),ct))).RequireErpPermission(DisbursementPosting.Permission);
        g.MapGet("/accounts",async(long empresaId,DisbursementPosting repo,CancellationToken ct)=>Results.Ok(await repo.AccountsAsync(empresaId,ct))).RequireErpPermission(DisbursementPosting.Permission);
        g.MapGet("/cash-chart",async(long empresaId,ZeusRepository repo,ZeusTransport transport,CancellationToken ct)=>{
            var config=(await repo.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus primero.")).Configuracion;
            return Results.Ok(new{cuentas=await transport.CashAccountsAsync(empresaId,config,ct),medios=await transport.PaymentCurrenciesAsync(empresaId,config,ct)});
        }).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        g.MapGet("/cash-configuration",async(long empresaId,DisbursementRepository options,DisbursementPosting repo,CancellationToken ct)=>Results.Ok(new{opts=await options.OptionsAsync(empresaId,null,null,ct),saved=await repo.AccountsAsync(empresaId,ct)})).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
        g.MapPut("/accounts",async(long empresaId,CashAccount input,HttpContext http,DisbursementPosting repo,ZeusRepository settings,ZeusTransport transport,CancellationToken ct)=>{
            var config=(await settings.SettingsAsync(empresaId,ct)??throw new ArgumentException("Configura Zeus primero.")).Configuracion;
            var account=(await transport.CashAccountsAsync(empresaId,config,ct)).SingleOrDefault(a=>a.Codigo==input.Cuenta)??throw new ArgumentException("Cuenta de caja/banco no válida en Zeus.");
            var currency=(await transport.PaymentCurrenciesAsync(empresaId,config,ct)).SingleOrDefault(m=>m.Codigo==input.MonedaZeus)??throw new ArgumentException("Selecciona el medio de pago del catálogo MONEDAS de Zeus.");
            if(input.MedioPago=="EFECTIVO"&&currency.Tipo is not(0 or 1)||input.MedioPago=="CHEQUE"&&currency.Tipo is not(2 or 8)||input.MedioPago=="TRANSFERENCIA"&&currency.Tipo is 0 or 1 or 2 or 8)throw new ArgumentException("El tipo del medio de pago Zeus no corresponde a efectivo, cheque o transferencia elegida.");
            await repo.SaveAccountAsync(empresaId,input,Convert.ToInt64(http.Items["UsuarioId"]),config,account,ct);return Results.NoContent();
        }).RequireErpPermission("SEGURIDAD.PERMISOS.ADMINISTRAR");
    }
}
