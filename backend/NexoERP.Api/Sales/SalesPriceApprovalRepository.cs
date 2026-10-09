using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record SalesPriceApprovalRequest(SalesInvoiceInput Factura,string Motivo);
public sealed record SalesPriceApprovalDecision(string Respuesta);

public sealed class SalesPriceApprovalRepository(TenantConnectionFactory connections)
{
    public static string Hash(SalesInvoiceInput input)
    {
        var json=JsonSerializer.Serialize(input with{AutorizacionVentaId=null});
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(json)));
    }

    public async Task<object> RequestAsync(long company,SalesPriceApprovalRequest request,long user,CancellationToken ct)
    {
        var input=request.Factura;
        var reason=request.Motivo?.Trim()??"";
        if(reason.Length is <10 or >500||input.OperacionGuid==Guid.Empty||input.ClienteId<=0||input.SucursalId<=0
            ||string.IsNullOrWhiteSpace(input.Numero)||input.Numero.Length>15||input.Lineas is not {Length: >0 and <=100}
            ||input.AutorizacionVentaId is not null)
            throw new ArgumentException("Completa la factura y explica en 10 a 500 caracteres por qué necesitas autorización.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT MaxDescuentoVentaPct FROM core.Empresa WITH(HOLDLOCK) WHERE EmpresaId=@E",company,tx);
        var maxDiscount=Convert.ToDecimal(await q.ExecuteScalarAsync(ct));
        ZeusRepository.Add(q,"@Branch",input.SucursalId);
        var issues=new List<SalesPricing.ExceptionDetail>();
        foreach(var line in input.Lineas)
        {
            if(line.ArticuloId<=0||line.BodegaId<=0||line.Cantidad<=0||line.PrecioUnitarioConIva<=0)
                throw new ArgumentException("Revisa los artículos, bodegas, cantidades y precios antes de solicitar autorización.");
            ZeusRepository.Add(q,"@Article",line.ArticuloId);ZeusRepository.Add(q,"@Warehouse",line.BodegaId);
            q.CommandText="""
                SELECT a.PrecioListaConIva,ISNULL(s.CostoPromedio,0),a.PorcentajeIvaVenta,a.ManejaInventario,a.Codigo,a.Descripcion
                FROM inv.Articulo a
                JOIN inv.Bodega b ON b.EmpresaId=a.EmpresaId AND b.BodegaId=@Warehouse AND b.SucursalId=@Branch AND b.Activa=1
                LEFT JOIN inv.SaldoArticuloBodega s ON s.EmpresaId=a.EmpresaId AND s.ArticuloId=a.ArticuloId AND s.BodegaId=b.BodegaId
                WHERE a.EmpresaId=@E AND a.ArticuloId=@Article AND a.Activo=1
                """;
            await using(var r=await q.ExecuteReaderAsync(ct))
            {
                if(!await r.ReadAsync(ct)||r.IsDBNull(2))throw new ArgumentException("Un artículo no está activo en la sucursal o no tiene IVA configurado.");
                issues.AddRange(SalesPricing.Assess(line.PrecioUnitarioConIva,r.IsDBNull(0)?null:r.GetDecimal(0),maxDiscount,
                    r.GetDecimal(1),r.GetDecimal(2),r.GetBoolean(3),line.ArticuloId,line.BodegaId,r.GetString(4)+" · "+r.GetString(5),
                    line.PrecioBaseConIva,line.DescuentoPorcentaje));
            }
            q.Parameters.RemoveAt("@Article");q.Parameters.RemoveAt("@Warehouse");
        }
        if(issues.Count==0)throw new ArgumentException("Esta factura no supera el descuento libre ni está por debajo del costo; no requiere autorización.");
        var hash=Hash(input);
        ZeusRepository.Add(q,"@Key",input.OperacionGuid);
        q.CommandText="SELECT AutorizacionPrecioVentaId,Huella,Estado FROM ven.AutorizacionPrecioVenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND OperacionGuid=@Key";
        await using(var prior=await q.ExecuteReaderAsync(ct))
            if(await prior.ReadAsync(ct))
            {
                if(prior.GetString(1)!=hash)throw new ArgumentException("Ya existe una solicitud con esta clave para otra versión de la factura. Inicia una factura nueva.");
                var id=prior.GetInt64(0);var status=prior.GetString(2);await prior.CloseAsync();await tx.CommitAsync(ct);
                return new{id,estado=status,repetido=true};
            }
        ZeusRepository.Add(q,"@Invoice",JsonSerializer.Serialize(input));ZeusRepository.Add(q,"@Hash",hash);
        ZeusRepository.Add(q,"@Issues",JsonSerializer.Serialize(issues));ZeusRepository.Add(q,"@Reason",reason);ZeusRepository.Add(q,"@User",user);
        q.CommandText="""
            INSERT ven.AutorizacionPrecioVenta(EmpresaId,ClienteId,OperacionGuid,FacturaJson,Huella,ExcepcionesJson,Motivo,SolicitadoPor)
            OUTPUT inserted.AutorizacionPrecioVentaId VALUES(@E,@Client,@Key,@Invoice,@Hash,@Issues,@Reason,@User)
            """;
        ZeusRepository.Add(q,"@Client",input.ClienteId);
        var created=Convert.ToInt64(await q.ExecuteScalarAsync(ct));
        ZeusRepository.Add(q,"@Id",created);
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'SOLICITAR_PRECIO_VENTA','ven.AutorizacionPrecioVenta',CONVERT(varchar(30),@Id),@Issues,'ERP')";
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
        return new{id=created,estado="PENDIENTE",repetido=false};
    }

    public async Task<object> ListAsync(long company,long user,bool administrator,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT TOP(100) a.AutorizacionPrecioVentaId,a.FacturaJson,a.ExcepcionesJson,a.Motivo,a.Estado,a.SolicitadoPor,a.ResueltoPor,
                a.SolicitadoEnUtc,a.ResueltoEnUtc,a.Respuesta,a.FacturaVentaId,t.RazonSocial
            FROM ven.AutorizacionPrecioVenta a
            JOIN ter.Tercero t ON t.EmpresaId=a.EmpresaId AND t.TerceroId=a.ClienteId
            WHERE a.EmpresaId=@E AND (@Admin=1 OR a.SolicitadoPor=@User)
            ORDER BY a.AutorizacionPrecioVentaId DESC
            """,company);
        ZeusRepository.Add(q,"@Admin",administrator);ZeusRepository.Add(q,"@User",user);
        var items=new List<object>();await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))
        {
            var invoice=JsonSerializer.Deserialize<SalesInvoiceInput>(r.GetString(1))!;
            items.Add(new{id=r.GetInt64(0),numero=invoice.Numero,clienteId=invoice.ClienteId,cliente=r.GetString(11),
                cuotas=invoice.Cuotas,primerVencimiento=invoice.Vencimiento.ToString("yyyy-MM-dd"),
                totalEstimado=(invoice.Lineas??[]).Sum(x=>x.Cantidad*x.PrecioUnitarioConIva)+(invoice.Conceptos??[]).Sum(x=>x.Valor),
                excepciones=JsonSerializer.Deserialize<SalesPricing.ExceptionDetail[]>(r.GetString(2)),motivo=r.GetString(3),
                estado=r.GetString(4),solicitadoPor=r.GetInt64(5),propia=r.GetInt64(5)==user,puedeResolver=administrator&&r.GetInt64(5)!=user,
                resueltoPor=r.IsDBNull(6)?(long?)null:r.GetInt64(6),
                solicitadoEn=r.GetDateTime(7),resueltoEn=r.IsDBNull(8)?(DateTime?)null:r.GetDateTime(8),
                respuesta=r.IsDBNull(9)?null:r.GetString(9),facturaId=r.IsDBNull(10)?(long?)null:r.GetInt64(10)});
        }
        return new{items};
    }

    public async Task DecideAsync(long company,long id,long user,bool approve,string? response,CancellationToken ct)
    {
        response=response?.Trim();
        if(!approve&&string.IsNullOrWhiteSpace(response))throw new ArgumentException("Explica el rechazo de la solicitud.");
        if(response?.Length>500)throw new ArgumentException("La respuesta admite máximo 500 caracteres.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"""
            UPDATE ven.AutorizacionPrecioVenta SET Estado=@Status,ResueltoPor=@User,ResueltoEnUtc=SYSUTCDATETIME(),Respuesta=@Response
            WHERE EmpresaId=@E AND AutorizacionPrecioVentaId=@Id AND Estado='PENDIENTE' AND SolicitadoPor<>@User
            """,company,tx);
        ZeusRepository.Add(q,"@Id",id);ZeusRepository.Add(q,"@User",user);ZeusRepository.Add(q,"@Status",approve?"APROBADA":"RECHAZADA");
        ZeusRepository.Add(q,"@Response",(object?)response??DBNull.Value);
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("La solicitud ya no está pendiente o intentas aprobar tu propia venta.");
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,@Action,'ven.AutorizacionPrecioVenta',CONVERT(varchar(30),@Id),@Response,'ERP')";
        ZeusRepository.Add(q,"@Action",approve?"APROBAR_PRECIO_VENTA":"RECHAZAR_PRECIO_VENTA");
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
    }

    public async Task<SalesInvoiceInput> ApprovedInvoiceAsync(long company,long id,long user,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT FacturaJson FROM ven.AutorizacionPrecioVenta WHERE EmpresaId=@E AND AutorizacionPrecioVentaId=@Id AND Estado='APROBADA' AND SolicitadoPor=@User",company);
        ZeusRepository.Add(q,"@Id",id);ZeusRepository.Add(q,"@User",user);
        var json=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("La solicitud no está aprobada o pertenece a otro vendedor.");
        return JsonSerializer.Deserialize<SalesInvoiceInput>(json)! with{AutorizacionVentaId=id};
    }
}
