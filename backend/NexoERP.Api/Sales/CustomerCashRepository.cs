using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record CashReceiptApplication(long FacturaVentaId,decimal Valor,long? FacturaVentaCuotaId=null);
public sealed record CashReceiptInput(Guid OperacionGuid,long SucursalId,long ClienteId,DateOnly FechaContable,
    string Tipo,string MedioPago,string? Referencia,string Concepto,decimal Total,string? CuentaContrapartida,
    CashReceiptApplication[] Aplicaciones);

public sealed class CustomerCashRepository(TenantConnectionFactory connections)
{
    public async Task<object> ListAsync(long company,string? search,long? before,CancellationToken ct)
    {
        search=search?.Trim()??"";if(search.Length>100)throw new ArgumentException("Búsqueda demasiado larga.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT TOP(51) r.ReciboCajaId,r.FechaContable,r.Tipo,t.RazonSocial,r.Total,r.ZeusEstado,r.ZeusFuente,r.ZeusDocumento,r.ZeusError
            FROM cxc.ReciboCaja r JOIN ter.Tercero t ON t.EmpresaId=r.EmpresaId AND t.TerceroId=r.ClienteId
            WHERE r.EmpresaId=@E AND (@Before IS NULL OR r.ReciboCajaId<@Before)
              AND (@Q='' OR r.ReciboCajaId=TRY_CONVERT(bigint,@Q) OR t.RazonSocial LIKE '%'+@Q+'%'
                   OR t.NumeroIdentificacion LIKE '%'+@Q+'%' OR r.ZeusDocumento LIKE '%'+@Q+'%')
            ORDER BY r.ReciboCajaId DESC;
            """,company);
        q.Parameters.Add("@Q",SqlDbType.NVarChar,100).Value=search;
        q.Parameters.Add("@Before",SqlDbType.BigInt).Value=(object?)before??DBNull.Value;
        var list=new List<object>();long? next=null;await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))
        {
            if(list.Count==50)return new{items=list,siguiente=next};
            next=r.GetInt64(0);list.Add(new{id=next,fecha=r.GetDateTime(1).ToString("yyyy-MM-dd"),tipo=r.GetString(2),cliente=r.GetString(3),total=r.GetDecimal(4),zeusEstado=r.GetString(5),fuente=r.IsDBNull(6)?null:r.GetString(6),documento=r.IsDBNull(7)?null:r.GetString(7),error=r.IsDBNull(8)?null:r.GetString(8)});
        }
        return new{items=list,siguiente=(long?)null};
    }
    public async Task<object> OptionsAsync(long company,long? customer,string? search,CancellationToken ct)
    {
        search=search?.Trim()??"";
        if(search.Length>100)throw new ArgumentException("La búsqueda admite máximo 100 caracteres.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT SucursalId,Codigo,Nombre FROM core.Sucursal WHERE EmpresaId=@E AND Activa=1 ORDER BY Codigo;
            SELECT TOP(50) t.TerceroId,t.NumeroIdentificacion,t.RazonSocial FROM ter.Tercero t
            JOIN ven.ClientePerfil p ON p.EmpresaId=t.EmpresaId AND p.TerceroId=t.TerceroId
            WHERE t.EmpresaId=@E AND t.Activo=1 AND (@Q='' OR t.RazonSocial LIKE '%'+@Q+'%' OR t.NumeroIdentificacion LIKE '%'+@Q+'%' OR t.TerceroId=@C)
            ORDER BY CASE WHEN t.TerceroId=@C THEN 0 ELSE 1 END,t.RazonSocial;
            SELECT f.FacturaVentaId,f.Numero,f.FechaContable,COALESCE(c.FechaVencimiento,f.Vencimiento),
                COALESCE(c.ValorOriginal,f.Total),COALESCE(c.SaldoPendiente,f.SaldoPendiente),f.ZeusEstado,
                c.FacturaVentaCuotaId,c.NumeroCuota
            FROM ven.FacturaVenta f LEFT JOIN ven.FacturaVentaCuota c ON c.EmpresaId=f.EmpresaId AND c.FacturaVentaId=f.FacturaVentaId
            WHERE f.EmpresaId=@E AND f.ClienteId=@C AND f.SaldoPendiente>0
                AND (c.FacturaVentaCuotaId IS NULL OR c.SaldoPendiente>0)
            ORDER BY COALESCE(c.FechaVencimiento,f.Vencimiento),f.FacturaVentaId,c.NumeroCuota;
            SELECT ReciboCajaId,Saldo FROM cxc.AnticipoCliente WHERE EmpresaId=@E AND ClienteId=@C AND Saldo>0 ORDER BY ReciboCajaId;
            SELECT SucursalId,MedioPago,Cuenta,Nombre FROM cxp.EgresoCuentaSucursal WHERE EmpresaId=@E;
            """,company);
        q.Parameters.Add("@Q",SqlDbType.NVarChar,100).Value=search;
        q.Parameters.Add("@C",SqlDbType.BigInt).Value=(object?)customer??DBNull.Value;
        var branches=new List<object>();var clients=new List<object>();var invoices=new List<object>();var advances=new List<object>();var accounts=new List<object>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))branches.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),nombre=r.GetString(2)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))clients.Add(new{id=r.GetInt64(0),identificacion=r.GetString(1),nombre=r.GetString(2)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))invoices.Add(new{id=r.GetInt64(0),numero=r.GetString(1),fecha=r.GetDateTime(2).ToString("yyyy-MM-dd"),vence=r.GetDateTime(3).ToString("yyyy-MM-dd"),total=r.GetDecimal(4),saldo=r.GetDecimal(5),zeusEstado=r.GetString(6),cuotaId=r.IsDBNull(7)?(long?)null:r.GetInt64(7),numeroCuota=r.IsDBNull(8)?(int?)null:r.GetInt32(8)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))advances.Add(new{id=r.GetInt64(0),saldo=r.GetDecimal(1)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))accounts.Add(new{sucursalId=r.GetInt64(0),medioPago=r.GetString(1),cuenta=r.GetString(2),nombre=r.GetString(3)});
        return new{sucursales=branches,clientes=clients,facturas=invoices,anticipos=advances,cuentas=accounts};
    }

    public async Task<object> PostAsync(long company,CashReceiptInput input,long user,CancellationToken ct)
    {
        if(input.OperacionGuid==Guid.Empty||input.SucursalId<=0||input.ClienteId<=0||input.FechaContable.Year<2000)
            throw new ArgumentException("Selecciona sucursal, cliente y fecha contable.");
        if(input.Tipo is not("ANTICIPO" or "CARTERA" or "NORMAL")||input.MedioPago is not("EFECTIVO" or "TRANSFERENCIA" or "CHEQUE"))
            throw new ArgumentException("Tipo de recibo o medio de pago no válido.");
        if(input.Total<=0||input.Total>1_000_000_000_000m||decimal.Round(input.Total,2)!=input.Total)
            throw new ArgumentException("El valor del recibo debe ser positivo y tener máximo dos decimales.");
        if(string.IsNullOrWhiteSpace(input.Concepto)||input.Concepto.Length>300||input.Referencia?.Length>20)
            throw new ArgumentException("Escribe un concepto y una referencia válida.");
        var applications=input.Aplicaciones??[];
        if(input.Tipo=="CARTERA")
        {
            if(applications.Length is <1 or >120||applications.Any(a=>a.FacturaVentaId<=0||a.FacturaVentaCuotaId is <=0||a.Valor<=0||decimal.Round(a.Valor,2)!=a.Valor)
                ||applications.GroupBy(a=>(a.FacturaVentaId,a.FacturaVentaCuotaId)).Any(g=>g.Count()>1)||applications.Sum(a=>a.Valor)!=input.Total)
                throw new ArgumentException("Los abonos deben ser únicos, positivos y sumar exactamente el valor del recibo.");
        }
        else if(applications.Length!=0)throw new ArgumentException("Solo un recaudo de cartera puede aplicar facturas.");
        if(input.Tipo=="NORMAL"&&string.IsNullOrWhiteSpace(input.CuentaContrapartida))
            throw new ArgumentException("Selecciona la cuenta de ingreso para el recibo normal.");
        if(input.Tipo!="NORMAL"&&!string.IsNullOrWhiteSpace(input.CuentaContrapartida))
            throw new ArgumentException("La cuenta de anticipo/cartera se toma de la configuración, no se digita.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT ReciboCajaId,Contenido FROM cxc.ReciboCaja WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND OperacionGuid=@Key",company,tx);
        ZeusRepository.Add(q,"@Key",input.OperacionGuid);
        await using(var prior=await q.ExecuteReaderAsync(ct))
            if(await prior.ReadAsync(ct))
            {
                if(prior.GetString(1)!=JsonSerializer.Serialize(input))throw new ArgumentException("La clave de operación ya corresponde a otro recibo. Actualiza y vuelve a intentarlo.");
                var priorId=prior.GetInt64(0);await prior.CloseAsync();await tx.CommitAsync(ct);
                return new{id=priorId,estado="CONTABILIZADO",repetido=true};
            }
        ZeusRepository.Add(q,"@B",input.SucursalId);ZeusRepository.Add(q,"@C",input.ClienteId);
        ZeusRepository.Add(q,"@Date",input.FechaContable.ToDateTime(TimeOnly.MinValue));
        q.CommandText="SELECT COUNT(*) FROM core.PeriodoInventario WHERE EmpresaId=@E AND Estado IN('ABIERTO','REABIERTO') AND @Date BETWEEN FechaInicio AND FechaFin";
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new ArgumentException("Abre el período de la fecha contable antes de registrar el recibo.");
        q.CommandText="SELECT Nombre FROM core.Sucursal WHERE EmpresaId=@E AND SucursalId=@B AND Activa=1";
        var branch=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Sucursal inexistente o inactiva.");
        q.CommandText="SELECT t.RazonSocial,t.NumeroIdentificacion,p.ZeusEstado FROM ter.Tercero t JOIN ven.ClientePerfil p ON p.EmpresaId=t.EmpresaId AND p.TerceroId=t.TerceroId WHERE t.EmpresaId=@E AND t.TerceroId=@C AND t.Activo=1";
        string customer,identification;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("Selecciona un cliente activo.");
            customer=r.GetString(0);identification=r.GetString(1);
            if(r.GetString(2) is not("TERCERO" or "CLIENTE"))throw new ArgumentException("Espera a que el tercero del cliente esté confirmado en Zeus antes de recibir dinero.");
        }
        q.CommandText="SELECT Cuenta,Banco,MonedaZeus,Servidor,BaseDatos FROM cxp.EgresoCuentaSucursal WHERE EmpresaId=@E AND SucursalId=@B AND MedioPago=@Method";
        ZeusRepository.Add(q,"@Method",input.MedioPago);
        string cashAccount,bank,paymentCurrency,accountServer,accountDb;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("Configura caja/banco para esta sucursal y medio de pago en Integración Zeus.");
            cashAccount=r.GetString(0);bank=r.GetString(1);paymentCurrency=r.GetString(2);accountServer=r.GetString(3);accountDb=r.GetString(4);
        }
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WHERE EmpresaId=@E";
        var settings=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Configura Zeus para esta empresa."))!;
        if(!settings.Habilitado)throw new ArgumentException("Habilita Zeus antes de contabilizar recibos.");
        if(accountServer!=settings.ServidorEsperado||accountDb!=settings.BaseEsperada)
            throw new ArgumentException("La cuenta de caja/banco pertenece a otro destino Zeus. Configúrala nuevamente.");
        if(!(settings.FuentesAutomaticas??[]).Any(x=>x.Movimiento=="RECIBO_CAJA"&&x.SucursalId==input.SucursalId))
            throw new ArgumentException("Configura la fuente RECIBO_CAJA de esta sucursal.");
        settings=ZeusRouting.Resolve(settings,input.SucursalId,"RECIBO_CAJA",branch);
        if(input.Tipo=="ANTICIPO"&&ZeusJournal.GeneralAdvanceAccount(settings) is null)
            throw new ArgumentException("Configura la cuenta general de anticipos de clientes en Zeus.");
        if(input.Tipo=="NORMAL"&&(input.CuentaContrapartida!.Length>16||input.CuentaContrapartida==cashAccount))
            throw new ArgumentException("Selecciona una cuenta de ingreso válida, diferente de caja/banco.");
        var invoiceApplications=new List<ZeusCustomerInvoice>();
        foreach(var line in applications.OrderBy(x=>x.FacturaVentaId).ThenBy(x=>x.FacturaVentaCuotaId))
        {
            ZeusRepository.Add(q,"@Invoice",line.FacturaVentaId);ZeusRepository.Add(q,"@Value",line.Valor);
            ZeusRepository.Add(q,"@Installment",(object?)line.FacturaVentaCuotaId??DBNull.Value);
            q.CommandText="""
                SELECT f.SaldoPendiente,f.ZeusEstado,f.Numero,f.Vencimiento,f.Snapshot,c.SaldoPendiente,c.FechaVencimiento,
                    f.ZeusDocumento,
                    CASE WHEN EXISTS(SELECT 1 FROM ven.FacturaVentaCuota x WHERE x.EmpresaId=f.EmpresaId AND x.FacturaVentaId=f.FacturaVentaId) THEN 1 ELSE 0 END
                FROM ven.FacturaVenta f WITH(UPDLOCK,HOLDLOCK)
                LEFT JOIN ven.FacturaVentaCuota c WITH(UPDLOCK,HOLDLOCK)
                    ON c.EmpresaId=f.EmpresaId AND c.FacturaVentaId=f.FacturaVentaId AND c.FacturaVentaCuotaId=@Installment
                WHERE f.EmpresaId=@E AND f.FacturaVentaId=@Invoice AND f.ClienteId=@C AND f.FechaContable<=@Date
                """;
            await using(var reader=await q.ExecuteReaderAsync(ct))
            {
                if(!await reader.ReadAsync(ct)||reader.GetDecimal(0)<line.Valor||reader.GetString(1)!="CONTABILIZADO")
                    throw new ArgumentException("Una factura no pertenece al cliente, no tiene saldo suficiente o aún no fue confirmada en Zeus.");
                if(line.FacturaVentaCuotaId.HasValue&&(reader.IsDBNull(5)||reader.GetDecimal(5)<line.Valor))
                    throw new ArgumentException("La cuota no pertenece a esta factura o su saldo cambió.");
                if(!line.FacturaVentaCuotaId.HasValue&&reader.GetInt32(8)!=0)
                    throw new ArgumentException("Selecciona una cuota concreta para aplicar el recaudo de esta factura.");
                if(reader.IsDBNull(4))throw new ArgumentException("La factura no tiene comprobante Zeus verificable.");
                var original=JsonSerializer.Deserialize<ZeusSnapshot>(reader.GetString(4))!;
                if(original.Configuracion.ServidorEsperado!=settings.ServidorEsperado||original.Configuracion.BaseEsperada!=settings.BaseEsperada)
                    throw new ArgumentException("La factura pertenece a otro destino Zeus. Concíliala antes de recaudar.");
                var account=original.ClienteDocumento?.CuentaCliente??throw new ArgumentException("La factura no tiene cuenta de cartera de cliente.");
                var invoiceNumber=reader.GetString(2);
                if(original.ClienteDocumento?.FacturaUsaConsecutivoZeus==true)
                {
                    if(reader.IsDBNull(7))throw new ArgumentException("La factura aún no tiene consecutivo confirmado en Zeus.");
                    var document=reader.GetString(7).Trim();
                    if(document.Length!=10||!document.StartsWith(original.Configuracion.Serie,StringComparison.Ordinal)||!document[2..].All(char.IsDigit))
                        throw new ArgumentException("El consecutivo de Zeus de la factura no coincide con su serie. Concíliala antes de recaudar.");
                    invoiceNumber=document[2..];
                }
                invoiceApplications.Add(new(line.FacturaVentaId,account,original.Configuracion.TipoFactura,invoiceNumber,original.Configuracion.UnidadNegocio,
                    line.FacturaVentaCuotaId.HasValue?reader.GetDateTime(6):reader.GetDateTime(3),line.Valor));
            }
            q.Parameters.RemoveAt("@Invoice");q.Parameters.RemoveAt("@Value");q.Parameters.RemoveAt("@Installment");
        }
        ZeusRepository.Add(q,"@Type",input.Tipo);ZeusRepository.Add(q,"@Concept",input.Concepto.Trim());
        ZeusRepository.Add(q,"@Ref",input.Referencia?.Trim()??"");ZeusRepository.Add(q,"@Total",input.Total);
        ZeusRepository.Add(q,"@Contra",input.CuentaContrapartida?.Trim()??"");ZeusRepository.Add(q,"@Json",JsonSerializer.Serialize(input));ZeusRepository.Add(q,"@User",user);
        q.CommandText="INSERT cxc.ReciboCaja(EmpresaId,OperacionGuid,SucursalId,ClienteId,FechaContable,Tipo,MedioPago,Referencia,Concepto,CuentaContrapartida,Total,Contenido,CreadoPor) OUTPUT inserted.ReciboCajaId VALUES(@E,@Key,@B,@C,@Date,@Type,@Method,@Ref,@Concept,NULLIF(@Contra,''),@Total,@Json,@User)";
        var id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));ZeusRepository.Add(q,"@Id",id);
        if(input.Tipo=="ANTICIPO")
        {
            q.CommandText="INSERT cxc.AnticipoCliente(EmpresaId,ReciboCajaId,ClienteId,Saldo) VALUES(@E,@Id,@C,@Total)";
            await q.ExecuteNonQueryAsync(ct);
        }
        foreach(var line in applications)
        {
            q.Parameters.Add("@Invoice",SqlDbType.BigInt).Value=line.FacturaVentaId;
            q.Parameters.Add("@Value",SqlDbType.Decimal).Value=line.Valor;
            q.Parameters.Add("@Installment",SqlDbType.BigInt).Value=(object?)line.FacturaVentaCuotaId??DBNull.Value;
            q.CommandText="""
                UPDATE ven.FacturaVenta SET SaldoPendiente=SaldoPendiente-@Value WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND ClienteId=@C AND SaldoPendiente>=@Value;
                IF @@ROWCOUNT<>1 THROW 52310,'El saldo de la factura cambió. Actualiza antes de cobrar.',1;
                IF @Installment IS NOT NULL
                BEGIN
                    UPDATE ven.FacturaVentaCuota SET SaldoPendiente=SaldoPendiente-@Value
                    WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND FacturaVentaCuotaId=@Installment AND SaldoPendiente>=@Value;
                    IF @@ROWCOUNT<>1 THROW 52310,'El saldo de la cuota cambió. Actualiza antes de cobrar.',1;
                END;
                INSERT cxc.ReciboCajaAplicacion(EmpresaId,ReciboCajaId,FacturaVentaId,FacturaVentaCuotaId,Valor)
                VALUES(@E,@Id,@Invoice,@Installment,@Value);
                """;
            await q.ExecuteNonQueryAsync(ct);q.Parameters.RemoveAt("@Invoice");q.Parameters.RemoveAt("@Value");q.Parameters.RemoveAt("@Installment");
        }
        var contra=input.Tipo switch
        {
            "ANTICIPO"=>ZeusJournal.GeneralAdvanceAccount(settings)!.Cuenta,
            "NORMAL"=>input.CuentaContrapartida!.Trim(),
            _=>""
        };
        var movements=invoiceApplications.Select(x=>new ZeusMovement(new ZeusAccount("CLIENTE",x.Cuenta),-x.Valor)).ToList();
        if(input.Tipo!="CARTERA")movements.Add(new(new ZeusAccount(input.Tipo=="ANTICIPO"?"ANTICIPO":"INGRESO",contra),-input.Total));
        movements.Add(new(new ZeusAccount("BANCO_CAJA",cashAccount),input.Total));
        var source=new ZeusSource(0,input.ClienteId,"RC-"+id,input.FechaContable.ToDateTime(TimeOnly.MinValue),input.FechaContable.ToDateTime(TimeOnly.MinValue),input.FechaContable.ToDateTime(TimeOnly.MinValue),input.Total,0,0,[],ProveedorNombre:customer);
        var snapshot=new ZeusSnapshot(settings,source,new(input.ClienteId,identification,identification),movements.ToArray(),
            ClienteDocumento:new("RECIBO",input.Concepto,"",bank,cashAccount,input.Referencia?.Trim()??"",paymentCurrency,invoiceApplications.ToArray()));
        q.CommandText="UPDATE cxc.ReciboCaja SET Snapshot=@Snapshot WHERE EmpresaId=@E AND ReciboCajaId=@Id";
        ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(snapshot));await q.ExecuteNonQueryAsync(ct);
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'CONTABILIZAR_RECIBO_CAJA','cxc.ReciboCaja',CONVERT(varchar(30),@Id),@Json,'ERP')";
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
        return new{id,estado="CONTABILIZADO",zeusEstado="PENDIENTE",cliente=customer,cuentaCaja=cashAccount,repetido=false};
    }
}
