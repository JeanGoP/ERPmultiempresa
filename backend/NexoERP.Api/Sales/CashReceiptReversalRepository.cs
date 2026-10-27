using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record CashReceiptReversalInput(DateOnly FechaContable,string Motivo);

public sealed class CashReceiptReversalRepository(TenantConnectionFactory connections)
{
    public async Task<object> RequestAsync(long company,long id,CashReceiptReversalInput input,long user,CancellationToken ct)
    {
        var reason=input.Motivo?.Trim()??"";
        if(reason.Length is <5 or >300||input.FechaContable.Year<2000)
            throw new ArgumentException("Indica fecha contable y motivo de reversión de al menos cinco caracteres.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT Tipo,ClienteId,Total,Snapshot,ZeusEstado,ReversionEstado,Concepto
            FROM cxc.ReciboCaja WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND ReciboCajaId=@Id
            """,company,tx);
        ZeusRepository.Add(q,"@Id",id);
        string type,concept;long customer;decimal total;ZeusSnapshot original;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("El recibo no existe.");
            if(r.GetString(4)!="CONTABILIZADO"||!r.IsDBNull(5))
                throw new ArgumentException("Solo se puede revertir un recibo confirmado en Zeus que no tenga otra reversión en curso.");
            type=r.GetString(0);customer=r.GetInt64(1);total=r.GetDecimal(2);concept=r.GetString(6);
            original=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(3))
                ??throw new ArgumentException("No se encuentra el comprobante original para reversar.");
        }
        ZeusRepository.Add(q,"@Customer",customer);
        ZeusRepository.Add(q,"@Date",input.FechaContable.ToDateTime(TimeOnly.MinValue));
        q.CommandText="SELECT COUNT(*) FROM core.PeriodoInventario WHERE EmpresaId=@E AND Estado IN('ABIERTO','REABIERTO') AND @Date BETWEEN FechaInicio AND FechaFin";
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)
            throw new ArgumentException("Abre el período de la fecha de reversión antes de continuar.");
        if(type=="ANTICIPO")
        {
            q.CommandText="SELECT Saldo FROM cxc.AnticipoCliente WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND ReciboCajaId=@Id";
            if(await q.ExecuteScalarAsync(ct) is not decimal balance||balance!=total)
                throw new ArgumentException("El anticipo ya fue aplicado. Revierte primero la factura que lo utilizó.");
        }
        if(type=="CARTERA")
        {
            q.CommandText="""
                SELECT COUNT(*) FROM cxc.ReciboCajaAplicacion a
                JOIN ven.FacturaVenta f WITH(UPDLOCK,HOLDLOCK) ON f.EmpresaId=a.EmpresaId AND f.FacturaVentaId=a.FacturaVentaId
                LEFT JOIN ven.FacturaVentaCuota cuota ON cuota.EmpresaId=a.EmpresaId AND cuota.FacturaVentaCuotaId=a.FacturaVentaCuotaId
                WHERE a.EmpresaId=@E AND a.ReciboCajaId=@Id
                    AND (f.RefinanciacionEstado<>'LIBRE' OR (a.FacturaVentaCuotaId IS NOT NULL
                        AND (cuota.EstadoPlan<>'ACTIVA' OR cuota.PlanVersion<>f.PlanVersion)))
                """;
            if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=0)
                throw new ArgumentException("Una factura ya cambió de plan. Revísala antes de revertir este recaudo.");
            q.CommandText="""
                SELECT COUNT(*) FROM cxc.ReciboCajaAplicacion a
                JOIN cxc.ReciboCajaAplicacion posterior ON posterior.EmpresaId=a.EmpresaId
                    AND posterior.FacturaVentaId=a.FacturaVentaId AND posterior.ReciboCajaId>a.ReciboCajaId
                JOIN cxc.ReciboCaja r ON r.EmpresaId=posterior.EmpresaId AND r.ReciboCajaId=posterior.ReciboCajaId
                WHERE a.EmpresaId=@E AND a.ReciboCajaId=@Id AND r.ZeusEstado<>'REVERTIDO'
                """;
            if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=0)
                throw new ArgumentException("Hay recaudos posteriores de esa factura. Revierte primero los más recientes.");
        }
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WITH(HOLDLOCK) WHERE EmpresaId=@E";
        var current=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string
            ??throw new ArgumentException("Configura Zeus para esta empresa."))!;
        if(!current.Habilitado||current.ServidorEsperado!=original.Configuracion.ServidorEsperado
            ||current.BaseEsperada!=original.Configuracion.BaseEsperada)
            throw new ArgumentException("El destino Zeus cambió o está deshabilitado; concilia antes de revertir.");
        q.CommandText="SELECT s.Nombre,r.SucursalId FROM cxc.ReciboCaja r JOIN core.Sucursal s ON s.EmpresaId=r.EmpresaId AND s.SucursalId=r.SucursalId WHERE r.EmpresaId=@E AND r.ReciboCajaId=@Id";
        string branch;long branchId;
        await using(var r=await q.ExecuteReaderAsync(ct)){await r.ReadAsync(ct);branch=r.GetString(0);branchId=r.GetInt64(1);}
        if(!(current.FuentesAutomaticas??[]).Any(x=>x.Movimiento=="RECIBO_CAJA"&&x.SucursalId==branchId))
            throw new ArgumentException("Configura una fuente activa de recibos de caja para esta sucursal.");
        var settings=ZeusRouting.Resolve(current,branchId,"RECIBO_CAJA",branch);
        var key=Guid.NewGuid();
        var source=original.Origen with{Factura=$"RC-{id}-REV",FechaContable=input.FechaContable.ToDateTime(TimeOnly.MinValue),
            FechaFactura=input.FechaContable.ToDateTime(TimeOnly.MinValue),Vencimiento=input.FechaContable.ToDateTime(TimeOnly.MinValue)};
        var receipt=original.ClienteDocumento??throw new ArgumentException("El recibo no tiene datos de aplicación Zeus.");
        var reverse=new ZeusSnapshot(settings,source,original.Proveedor,
            original.Movimientos.Select(m=>m with{Valor=-m.Valor}).ToArray(),
            ClienteDocumento:receipt with{Tipo="REVERSO_RECIBO",Concepto=$"REVERSIÓN RC-{id}: {reason}"[..Math.Min(120,$"REVERSIÓN RC-{id}: {reason}".Length)]});
        ZeusRepository.Add(q,"@Key",key);ZeusRepository.Add(q,"@Reason",reason);
        ZeusRepository.Add(q,"@User",user);ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(reverse));
        q.CommandText="""
            UPDATE cxc.ReciboCaja SET ReversionGuid=@Key,ReversionFecha=@Date,ReversionMotivo=@Reason,
                ReversionSnapshot=@Snapshot,ReversionEstado='PENDIENTE',ReversionPor=@User,
                ReversionActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND ReciboCajaId=@Id AND ZeusEstado='CONTABILIZADO' AND ReversionEstado IS NULL
            """;
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("El recibo cambió de estado. Actualiza la lista.");
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'SOLICITAR_REVERSION_RECIBO','cxc.ReciboCaja',CONVERT(varchar(30),@Id),@Audit,'ERP')";
        ZeusRepository.Add(q,"@Audit",JsonSerializer.Serialize(new{fecha=input.FechaContable,motivo=reason}));
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
        return new{id,reversionEstado="PENDIENTE"};
    }
}
