using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record PortfolioInstallment(DateOnly Vencimiento,decimal Valor,string Tipo="ORDINARIA");
public sealed record PortfolioRefinancingInput(Guid OperacionGuid,DateOnly FechaContable,string Motivo,
    PortfolioInstallment[] Cuotas,string? CuentaIngresoZeus,string? CentroCostoZeus);
public sealed record PortfolioOldInstallment(long Id,int Numero,DateOnly Vencimiento,decimal Saldo);

public sealed class PortfolioRefinancingRepository(TenantConnectionFactory connections,ZeusTransport zeus)
{
    public async Task CancelUnsentAsync(long company,long invoiceId,long noteId,long user,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"UPDATE ven.RefinanciacionCartera SET ZeusEstado='CANCELADO',ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND RefinanciacionCarteraId=@Id AND (ZeusEstado IN('POR_APROBAR','RECHAZADO') OR ZeusEstado='PENDIENTE' AND ZeusIntentos=0) AND ZeusDocumento IS NULL AND CreadoPor=@User",company,tx);
        ZeusRepository.Add(q,"@Invoice",invoiceId);ZeusRepository.Add(q,"@Id",noteId);ZeusRepository.Add(q,"@User",user);
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("Solo quien creó la nota puede descartar una nota aún no enviada. Si ya empezó el envío, espera su resultado o concíliala.");
        q.CommandText="UPDATE ven.FacturaVenta SET RefinanciacionEstado='LIBRE' WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND RefinanciacionEstado='PENDIENTE'";
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("La factura cambió; actualiza antes de descartar la nota.");
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen) VALUES(@E,@User,'CANCELAR_NOTA_CARTERA_SIN_ENVIO','ven.RefinanciacionCartera',CONVERT(varchar(30),@Id),'ERP')";
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
    }
    public async Task<object> ListAsync(long company,long invoiceId,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT RefinanciacionCarteraId,FechaContable,SaldoAnterior,NuevoSaldo,Incremento,Motivo,
                ZeusEstado,ZeusFuente,ZeusDocumento,ZeusError,PlanAnterior,PlanNuevo,CreadoPor,AprobadoPor,CuentaIngresoZeus,CentroCostoZeus,ZeusIntentos
            FROM ven.RefinanciacionCartera WHERE EmpresaId=@E AND FacturaVentaId=@Invoice
            ORDER BY RefinanciacionCarteraId DESC
            """,company);
        ZeusRepository.Add(q,"@Invoice",invoiceId);
        var items=new List<object>();await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))items.Add(new{id=r.GetInt64(0),fecha=r.GetDateTime(1).ToString("yyyy-MM-dd"),saldoAnterior=r.GetDecimal(2),nuevoSaldo=r.GetDecimal(3),incremento=r.GetDecimal(4),motivo=r.GetString(5),zeusEstado=r.GetString(6),fuente=r.IsDBNull(7)?null:r.GetString(7),documento=r.IsDBNull(8)?null:r.GetString(8),error=r.IsDBNull(9)?null:r.GetString(9),planAnterior=JsonSerializer.Deserialize<PortfolioOldInstallment[]>(r.GetString(10)),planNuevo=JsonSerializer.Deserialize<PortfolioInstallment[]>(r.GetString(11)),creadoPor=r.GetInt64(12),aprobadoPor=r.IsDBNull(13)?(long?)null:r.GetInt64(13),cuentaIngreso=r.IsDBNull(14)?null:r.GetString(14),centroCosto=r.IsDBNull(15)?null:r.GetString(15),intentos=r.GetInt32(16)});
        return new{items};
    }

    public async Task<object> CreateAsync(long company,long invoiceId,PortfolioRefinancingInput input,long user,CancellationToken ct)
    {
        if(input.OperacionGuid==Guid.Empty||input.FechaContable.Year<2000||string.IsNullOrWhiteSpace(input.Motivo)||input.Motivo.Trim().Length>300)
            throw new ArgumentException("Indica una fecha contable, un motivo y una clave de operación válidos.");
        var proposed=input.Cuotas??[];
        if(proposed.Length is <1 or >120||proposed.Any(x=>x.Vencimiento<input.FechaContable||x.Valor<=0||decimal.Round(x.Valor,2)!=x.Valor||x.Tipo is not("ORDINARIA" or "EXTRA"))
           ||proposed.Select(x=>x.Vencimiento).Distinct().Count()!=proposed.Length
           ||proposed.Zip(proposed.Skip(1)).Any(pair=>pair.First.Vencimiento>=pair.Second.Vencimiento))
            throw new ArgumentException("Envía de 1 a 120 cuotas ordenadas, con vencimientos distintos y valores positivos de dos decimales.");
        var newBalance=proposed.Sum(x=>x.Valor);
        if(newBalance>1_000_000_000_000m)throw new ArgumentException("El nuevo saldo excede el límite permitido.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT RefinanciacionCarteraId,FacturaVentaId,FechaContable,Motivo,PlanNuevo,CuentaIngresoZeus,CentroCostoZeus FROM ven.RefinanciacionCartera WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND OperacionGuid=@Key",company,tx);
        ZeusRepository.Add(q,"@Key",input.OperacionGuid);ZeusRepository.Add(q,"@Invoice",invoiceId);
        await using(var prior=await q.ExecuteReaderAsync(ct))if(await prior.ReadAsync(ct))
        {
            if(prior.GetInt64(1)!=invoiceId||DateOnly.FromDateTime(prior.GetDateTime(2))!=input.FechaContable||prior.GetString(3)!=input.Motivo.Trim()
               ||prior.GetString(4)!=JsonSerializer.Serialize(proposed)
               ||(prior.IsDBNull(5)?null:prior.GetString(5))!=input.CuentaIngresoZeus
               ||(prior.IsDBNull(6)?null:prior.GetString(6))!=input.CentroCostoZeus)
                throw new ArgumentException("La clave de operación ya corresponde a otra nota. Actualiza antes de reintentar.");
            var priorId=prior.GetInt64(0);await prior.CloseAsync();await tx.CommitAsync(ct);
            return new{id=priorId,repetido=true};
        }
        q.CommandText="""
            SELECT f.SucursalId,f.ClienteId,f.FechaContable,f.SaldoPendiente,f.ZeusEstado,
                f.RefinanciacionEstado,f.Snapshot,f.ZeusDocumento,f.PlanVersion,f.Numero,s.Nombre
            FROM ven.FacturaVenta f WITH(UPDLOCK,HOLDLOCK)
            JOIN core.Sucursal s ON s.EmpresaId=f.EmpresaId AND s.SucursalId=f.SucursalId
            WHERE f.EmpresaId=@E AND f.FacturaVentaId=@Invoice
            """;
        long branch,client;DateTime invoiceDate;decimal balance;int version;string invoiceNumber,branchName,document;
        ZeusSnapshot original;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)||r.GetString(4)!="CONTABILIZADO"||r.GetString(5)!="LIBRE"||r.GetDecimal(3)<=0||r.IsDBNull(6)||r.IsDBNull(7))
                throw new ArgumentException("La factura debe tener saldo, estar confirmada en Zeus y no tener otra refinanciación en proceso.");
            branch=r.GetInt64(0);client=r.GetInt64(1);invoiceDate=r.GetDateTime(2);balance=r.GetDecimal(3);
            original=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(6))??throw new ArgumentException("La factura no tiene comprobante Zeus válido.");
            document=r.GetString(7).Trim();version=r.GetInt32(8);invoiceNumber=r.GetString(9);branchName=r.GetString(10);
        }
        if(input.FechaContable.ToDateTime(TimeOnly.MinValue)<invoiceDate)
            throw new ArgumentException("La nota no puede tener fecha anterior a la factura.");
        if(original.ClienteDocumento is not { Tipo:"FACTURA" } customer ||
           string.IsNullOrWhiteSpace(customer.CuentaCliente)||original.Origen.ProveedorId!=client)
            throw new ArgumentException("La factura no tiene referencia de cartera verificable en Zeus.");
        if(customer.FacturaUsaConsecutivoZeus && (document.Length!=10||!document.StartsWith(original.Configuracion.Serie,StringComparison.Ordinal)||!document[2..].All(char.IsDigit)))
            throw new ArgumentException("El consecutivo de la factura no coincide con Zeus.");
        var actualInvoice=customer.FacturaUsaConsecutivoZeus
            ?customer.CarteraConsecutivoCompleto?document:document[2..]
            :original.Origen.Factura;
        var old=new List<PortfolioOldInstallment>();
        q.CommandText="""
            SELECT FacturaVentaCuotaId,NumeroCuota,FechaVencimiento,SaldoPendiente
            FROM ven.FacturaVentaCuota WITH(UPDLOCK,HOLDLOCK)
            WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND PlanVersion=@Version AND EstadoPlan='ACTIVA' AND SaldoPendiente>0
            ORDER BY NumeroCuota
            """;
        ZeusRepository.Add(q,"@Version",version);
        await using(var r=await q.ExecuteReaderAsync(ct))while(await r.ReadAsync(ct))
            old.Add(new(r.GetInt64(0),r.GetInt32(1),DateOnly.FromDateTime(r.GetDateTime(2)),r.GetDecimal(3)));
        if(old.Count==0||old.Sum(x=>x.Saldo)!=balance)
            throw new ArgumentException("El saldo de las cuotas no cuadra con la factura; concilia antes de refinanciar.");
        q.CommandText="""
            SELECT COUNT(*) FROM cxc.ReciboCajaAplicacion a
            JOIN cxc.ReciboCaja r ON r.EmpresaId=a.EmpresaId AND r.ReciboCajaId=a.ReciboCajaId
            WHERE a.EmpresaId=@E AND a.FacturaVentaId=@Invoice AND r.ZeusEstado<>'CONTABILIZADO'
            """;
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=0)
            throw new ArgumentException("Hay recaudos de esta factura sin confirmar en Zeus. Concílialos antes de refinanciar.");
        var increment=newBalance-balance;
        if(increment<0)throw new ArgumentException("La reducción de deuda requiere una cuenta y autorización de condonación; esta nota solo permite reprogramar o incrementar el saldo.");
        if(increment>0&&(string.IsNullOrWhiteSpace(input.CuentaIngresoZeus)||input.CuentaIngresoZeus.Length>16))
            throw new ArgumentException("Selecciona la cuenta de ingreso Zeus para el incremento de financiación.");
        if(input.CentroCostoZeus?.Length>16)throw new ArgumentException("Centro de costo Zeus demasiado largo.");
        q.CommandText="SELECT COUNT(*) FROM core.PeriodoInventario WHERE EmpresaId=@E AND Estado IN('ABIERTO','REABIERTO') AND @Date BETWEEN FechaInicio AND FechaFin";
        ZeusRepository.Add(q,"@Date",input.FechaContable.ToDateTime(TimeOnly.MinValue));
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new ArgumentException("Abre el período de la fecha contable antes de crear la nota.");
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WHERE EmpresaId=@E";
        var current=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Configura Zeus para la empresa."))!;
        if(!current.Habilitado||current.ServidorEsperado!=original.Configuracion.ServidorEsperado||current.BaseEsperada!=original.Configuracion.BaseEsperada)
            throw new ArgumentException("La factura pertenece a otro destino Zeus o la integración está deshabilitada.");
        if(!(current.FuentesAutomaticas??[]).Any(x=>x.Movimiento=="NOTA_CARTERA"&&x.SucursalId==branch))
            throw new ArgumentException("Configura una fuente de nota de cartera para esta sucursal en Integración Zeus.");
        var route=ZeusRouting.Resolve(current,branch,"NOTA_CARTERA",branchName);
        if(increment>0)
        {
            var chart=await zeus.ChartAsync(company,route,ct);
            if(!chart.Any(x=>x.Codigo==input.CuentaIngresoZeus&&x.Codigo.StartsWith("4",StringComparison.Ordinal)))
                throw new ArgumentException("Selecciona una cuenta de ingreso clase 4 habilitada y de detalle en Zeus.");
            var dims=await zeus.AccountingDimensionsAsync(company,route,ct);
            if(dims.CuentasRequierenCentroCosto.Contains(input.CuentaIngresoZeus!,StringComparer.OrdinalIgnoreCase)&&
               !dims.CentrosCosto.Any(x=>x.Codigo==input.CentroCostoZeus))
                throw new ArgumentException("Esta cuenta de ingreso requiere un centro de costo Zeus habilitado y de detalle.");
            if(!string.IsNullOrWhiteSpace(input.CentroCostoZeus)&&!dims.CentrosCosto.Any(x=>x.Codigo==input.CentroCostoZeus))
                throw new ArgumentException("Selecciona un centro de costo Zeus válido.");
        }
        var receivableMovement=original.Movimientos.FirstOrDefault(m=>m.Regla.Concepto=="CLIENTE")
            ??throw new ArgumentException("La factura no conserva su movimiento original de cartera en Zeus.");
        if(receivableMovement.Regla.Cuenta!=customer.CuentaCliente)
            throw new ArgumentException("La cuenta de cartera del comprobante no coincide con la factura guardada.");
        var receivable=receivableMovement.Regla with{Concepto="CLIENTE"};
        var moves=old.Select(x=>new ZeusMovement(receivable,-x.Saldo,VencimientoCartera:x.Vencimiento.ToDateTime(TimeOnly.MinValue),NumeroCuota:x.Numero))
            .Concat(proposed.Select((x,i)=>new ZeusMovement(receivable,x.Valor,VencimientoCartera:x.Vencimiento.ToDateTime(TimeOnly.MinValue),NumeroCuota:i+1))).ToList();
        if(increment>0)moves.Add(new(new ZeusAccount("REFINANCIACION_INGRESO",input.CuentaIngresoZeus!,CentroCosto:input.CentroCostoZeus?.Trim()??""),-increment));
        var date=input.FechaContable.ToDateTime(TimeOnly.MinValue);
        var source=new ZeusSource(0,client,invoiceNumber,date,original.Origen.FechaFactura,date,newBalance,0,0,[],ProveedorNombre:original.Origen.ProveedorNombre);
        var note=new ZeusPortfolioNote(original.Configuracion.TipoFactura,actualInvoice,original.Configuracion.UnidadNegocio,input.Motivo.Trim());
        var snapshot=new ZeusSnapshot(route,source,original.Proveedor,moves.ToArray(),NotaCartera:note);
        ZeusRepository.Add(q,"@Branch",branch);ZeusRepository.Add(q,"@Old",balance);ZeusRepository.Add(q,"@New",newBalance);
        ZeusRepository.Add(q,"@Increase",increment);ZeusRepository.Add(q,"@Account",(object?)input.CuentaIngresoZeus??DBNull.Value);
        ZeusRepository.Add(q,"@Center",(object?)input.CentroCostoZeus??DBNull.Value);
        ZeusRepository.Add(q,"@Reason",input.Motivo.Trim());ZeusRepository.Add(q,"@OldPlan",JsonSerializer.Serialize(old));
        ZeusRepository.Add(q,"@NewPlan",JsonSerializer.Serialize(proposed));ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(snapshot));
        ZeusRepository.Add(q,"@User",user);
        q.CommandText="""
            INSERT ven.RefinanciacionCartera(EmpresaId,FacturaVentaId,OperacionGuid,SucursalId,FechaContable,
                SaldoAnterior,NuevoSaldo,Incremento,CuentaIngresoZeus,CentroCostoZeus,Motivo,PlanAnterior,PlanNuevo,Snapshot,CreadoPor,ZeusEstado)
            OUTPUT inserted.RefinanciacionCarteraId
            VALUES(@E,@Invoice,@Key,@Branch,@Date,@Old,@New,@Increase,@Account,@Center,@Reason,@OldPlan,@NewPlan,@Snapshot,@User,'PENDIENTE')
            """;
        var id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));
        q.CommandText="UPDATE ven.FacturaVenta SET RefinanciacionEstado='PENDIENTE' WHERE EmpresaId=@E AND FacturaVentaId=@Invoice AND RefinanciacionEstado='LIBRE'";
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("La cartera cambió durante la preparación de la nota.");
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'REFINANCIAR_CARTERA','ven.RefinanciacionCartera',CONVERT(varchar(30),@Id),@NewPlan,'ERP')";
        ZeusRepository.Add(q,"@Id",id);await q.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        return new{id,zeusEstado="PENDIENTE",saldoAnterior=balance,nuevoSaldo=newBalance,incremento=increment,repetido=false};
    }
}
