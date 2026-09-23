using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Security;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Treasury;

public sealed record DisbursementLine(string Tipo,long? DocumentoPorPagarId,string Cuenta,string Concepto,decimal Valor);
public sealed record DisbursementDraft(Guid OperacionGuid,int Version,long SucursalId,long TerceroId,DateOnly FechaContable,
    string Moneda,string MedioPago,string BancoCaja,string CuentaSalida,string Referencia,string Concepto,DisbursementLine[] Lineas);
public sealed record DraftSaved(long Id,int Version);
public sealed class DraftConflict(string message):Exception(message);

public sealed class DisbursementRepository(TenantConnectionFactory connections)
{
    public static DisbursementDraft Validate(DisbursementDraft input)
    {
        static string Text(string? value,int max,string name,bool required=true)
        {
            value=value?.Trim()??"";
            if(required&&value.Length==0||value.Length>max||value.Any(char.IsControl))
                throw new ArgumentException($"Revisa {name}: {(required?"obligatorio, ":"")}máximo {max} caracteres.");
            return value;
        }
        if(input.OperacionGuid==Guid.Empty||input.Version<0||input.SucursalId<=0||input.TerceroId<=0||input.FechaContable.Year<2000)
            throw new ArgumentException("Faltan identificador de operación, sucursal, beneficiario o fecha contable válida.");
        var currency=Text(input.Moneda,3,"moneda").ToUpperInvariant();
        if(currency.Length!=3||currency.Any(c=>c<'A'||c>'Z'))throw new ArgumentException("La moneda debe tener tres letras.");
        if(input.MedioPago is not ("TRANSFERENCIA" or "EFECTIVO" or "CHEQUE"))throw new ArgumentException("Medio de pago no válido.");
        if(input.Lineas is null||input.Lineas.Length is <1 or >100)throw new ArgumentException("Agrega entre 1 y 100 conceptos.");
        var lines=input.Lineas.Select(l=>
        {
            if(l is null||l.Valor<=0||l.Valor>1000000000000m||decimal.Round(l.Valor,2)!=l.Valor)
                throw new ArgumentException("Cada abono/gasto debe ser positivo, máximo un billón y con hasta dos decimales.");
            if(l.Tipo is not ("FACTURA" or "GASTO")||l.Tipo=="FACTURA"&&l.DocumentoPorPagarId is not >0||l.Tipo=="GASTO"&&l.DocumentoPorPagarId is not null)
                throw new ArgumentException("Relaciona una obligación para FACTURA; GASTO no puede tener factura aplicada.");
            if(l.Tipo=="FACTURA"&&!string.IsNullOrWhiteSpace(l.Cuenta))throw new ArgumentException("La cuenta del proveedor proviene de la obligación; no se digita por factura.");
            return l with{Cuenta=Text(l.Cuenta,20,"cuenta del gasto",false),Concepto=Text(l.Concepto,200,"concepto de línea")};
        }).ToArray();
        if(lines.Where(l=>l.Tipo=="FACTURA").GroupBy(l=>l.DocumentoPorPagarId).Any(g=>g.Count()>1))
            throw new ArgumentException("Una factura no puede repetirse en el egreso.");
        if(lines.Sum(l=>l.Valor)>1000000000000m)
            throw new ArgumentException("El total del borrador no puede superar un billón.");
        return input with{Moneda=currency,BancoCaja=Text(input.BancoCaja,100,"banco o caja",false),
            CuentaSalida=Text(input.CuentaSalida,20,"cuenta de salida",false),Referencia=Text(input.Referencia,80,"referencia",false),
            Concepto=Text(input.Concepto,300,"concepto"),Lineas=lines};
    }

    public async Task<DraftSaved> SaveAsync(long company,long? id,DisbursementDraft input,long user,CancellationToken ct)
    {
        input=Validate(input);
        if(id is null&&input.Version!=0||id is not null&&input.Version<1)throw new ArgumentException("Versión de borrador no válida.");
        var json=JsonSerializer.Serialize(input);
        var hash=SHA256.HashData(Encoding.UTF8.GetBytes(json));
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT EgresoBorradorId,Version,Huella,OperacionGuid,Contenido FROM cxp.EgresoBorrador WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND OperacionGuid=@Key",company,tx);
        ZeusRepository.Add(q,"@Key",input.OperacionGuid);
        long? found=null;int version=0;byte[]? previousHash=null;string? previous=null;
        await using(var r=await q.ExecuteReaderAsync(ct))
            if(await r.ReadAsync(ct)){found=r.GetInt64(0);version=r.GetInt32(1);previousHash=(byte[])r[2];previous=r.GetString(4);}
        if(found is not null&&(id is null||id==found)&&previousHash!.SequenceEqual(hash))
        {await tx.CommitAsync(ct);return new(found.Value,version);}
        if(id is null&&found is not null||id is not null&&(found!=id||input.Version!=version))
            throw new DraftConflict("El borrador cambió o la operación ya existe. Abre la versión guardada antes de modificarlo.");

        q.CommandText="SELECT COUNT(*) FROM core.Sucursal WHERE EmpresaId=@E AND SucursalId=@Branch AND Activa=1";
        ZeusRepository.Add(q,"@Branch",input.SucursalId);
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new ArgumentException("Selecciona una sucursal activa de esta empresa.");
        q.CommandText="SELECT COUNT(*) FROM ter.Tercero WHERE EmpresaId=@E AND TerceroId=@Supplier AND Activo=1";
        ZeusRepository.Add(q,"@Supplier",input.TerceroId);
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new ArgumentException("El beneficiario no está activo en esta empresa.");
        foreach(var line in input.Lineas.Where(x=>x.Tipo=="FACTURA").OrderBy(x=>x.DocumentoPorPagarId))
        {
            q.CommandText="SELECT SaldoPendiente,FechaReconocimiento FROM cxp.DocumentoPorPagar WITH(HOLDLOCK) WHERE EmpresaId=@E AND DocumentoPorPagarId=@Payable AND TerceroId=@Supplier AND Moneda=@Currency AND Estado IN('ABIERTA','PARCIAL')";
            if(!q.Parameters.Contains("@Payable")){q.Parameters.Add("@Payable",SqlDbType.BigInt);ZeusRepository.Add(q,"@Currency",input.Moneda);}
            q.Parameters["@Payable"].Value=line.DocumentoPorPagarId!.Value;
            await using var r=await q.ExecuteReaderAsync(ct);
            if(!await r.ReadAsync(ct)||r.GetDecimal(0)<line.Valor||DateOnly.FromDateTime(r.GetDateTime(1))>input.FechaContable)
                throw new ArgumentException("La factura no pertenece al beneficiario/moneda, el abono supera el saldo o la fecha antecede su reconocimiento. Actualiza las facturas.");
        }
        var total=input.Lineas.Sum(x=>x.Valor);
        ZeusRepository.Add(q,"@Date",input.FechaContable.ToDateTime(TimeOnly.MinValue));
        if(!q.Parameters.Contains("@Currency"))ZeusRepository.Add(q,"@Currency",input.Moneda);
        ZeusRepository.Add(q,"@Json",json);ZeusRepository.Add(q,"@Hash",hash);ZeusRepository.Add(q,"@User",user);
        var amount=q.Parameters.Add("@Total",SqlDbType.Decimal);amount.Precision=18;amount.Scale=2;amount.Value=total;
        if(id is null)
        {
            q.CommandText="INSERT cxp.EgresoBorrador(EmpresaId,OperacionGuid,SucursalId,TerceroId,FechaContable,Moneda,Total,Contenido,Huella,CreadoPor,ActualizadoPor) OUTPUT inserted.EgresoBorradorId VALUES(@E,@Key,@Branch,@Supplier,@Date,@Currency,@Total,@Json,@Hash,@User,@User)";
            id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));version=1;
        }
        else
        {
            ZeusRepository.Add(q,"@Id",id.Value);
            q.CommandText="UPDATE cxp.EgresoBorrador SET SucursalId=@Branch,TerceroId=@Supplier,FechaContable=@Date,Moneda=@Currency,Total=@Total,Contenido=@Json,Huella=@Hash,Version=Version+1,ActualizadoPor=@User,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND EgresoBorradorId=@Id";
            await q.ExecuteNonQueryAsync(ct);version++;
        }
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'GUARDAR_BORRADOR_EGRESO','cxp.EgresoBorrador',@Entity,@Before,@Json,'ERP')";
        ZeusRepository.Add(q,"@Entity",id.Value.ToString());q.Parameters.Add("@Before",SqlDbType.NVarChar,-1).Value=(object?)previous??DBNull.Value;
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);return new(id.Value,version);
    }

    public async Task<object?> GetAsync(long company,long id,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT Version,Contenido FROM cxp.EgresoBorrador WHERE EmpresaId=@E AND EgresoBorradorId=@Id",company);
        ZeusRepository.Add(q,"@Id",id);await using var r=await q.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct)?new{id,estado="BORRADOR",datos=JsonSerializer.Deserialize<DisbursementDraft>(r.GetString(1))! with{Version=r.GetInt32(0)}}:null;
    }

    public async Task<object> ListAsync(long company,long? before,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT TOP(51) e.EgresoBorradorId,e.FechaContable,t.RazonSocial,e.Moneda,e.Total,e.Version FROM cxp.EgresoBorrador e JOIN ter.Tercero t ON t.EmpresaId=e.EmpresaId AND t.TerceroId=e.TerceroId WHERE e.EmpresaId=@E AND (@Before IS NULL OR e.EgresoBorradorId<@Before) ORDER BY e.EgresoBorradorId DESC",company);
        q.Parameters.Add("@Before",SqlDbType.BigInt).Value=(object?)before??DBNull.Value;
        await using var r=await q.ExecuteReaderAsync(ct);var rows=new List<object>();long? next=null;
        while(await r.ReadAsync(ct)){if(rows.Count==50){return new{items=rows,siguiente=next};}next=r.GetInt64(0);rows.Add(new{id=next,fecha=r.GetDateTime(1).ToString("yyyy-MM-dd"),beneficiario=r.GetString(2),moneda=r.GetString(3),total=r.GetDecimal(4),version=r.GetInt32(5),estado="BORRADOR"});}
        return new{items=rows,siguiente=(long?)null};
    }

    // Catálogos bajo el permiso de preparación, sin conceder administración ni lectura de otras empresas.
    public async Task<object> OptionsAsync(long company,string? search,long? supplier,CancellationToken ct)
    {
        if(search?.Length>120)throw new ArgumentException("Búsqueda demasiado larga.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT SucursalId,Codigo,Nombre FROM core.Sucursal WHERE EmpresaId=@E AND Activa=1 ORDER BY Codigo;
            SELECT TOP(101) TerceroId,NumeroIdentificacion,RazonSocial FROM ter.Tercero
            WHERE EmpresaId=@E AND Activo=1 AND (@Search='' OR RazonSocial LIKE '%'+@Search+'%' OR NumeroIdentificacion LIKE '%'+@Search+'%' OR TerceroId=@Supplier) ORDER BY CASE WHEN TerceroId=@Supplier THEN 0 ELSE 1 END,RazonSocial,TerceroId;
            SELECT p.DocumentoPorPagarId,d.NumeroDocumento,p.Moneda,p.SaldoPendiente,p.FechaReconocimiento,p.FechaVencimiento,p.ValorOriginal
            FROM cxp.DocumentoPorPagar p JOIN comp.DocumentoProveedor d ON d.EmpresaId=p.EmpresaId AND d.DocumentoProveedorId=p.DocumentoProveedorId
            WHERE p.EmpresaId=@E AND p.TerceroId=@Supplier AND p.SaldoPendiente>0 AND p.Estado IN('ABIERTA','PARCIAL') ORDER BY p.FechaVencimiento,p.DocumentoPorPagarId;
            """,company);
        ZeusRepository.Add(q,"@Search",search?.Trim()??"");q.Parameters.Add("@Supplier",SqlDbType.BigInt).Value=(object?)supplier??DBNull.Value;
        var branches=new List<object>();var suppliers=new List<object>();var invoices=new List<object>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))branches.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),nombre=r.GetString(2)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))suppliers.Add(new{id=r.GetInt64(0),identificacion=r.GetString(1),nombre=r.GetString(2)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))invoices.Add(new{id=r.GetInt64(0),numero=r.GetString(1),moneda=r.GetString(2),saldo=r.GetDecimal(3),fecha=r.GetDateTime(4).ToString("yyyy-MM-dd"),vence=r.GetDateTime(5).ToString("yyyy-MM-dd"),original=r.GetDecimal(6)});
        return new{sucursales=branches,beneficiarios=suppliers.Take(100),masBeneficiarios=suppliers.Count>100,facturas=invoices,masFacturas=false};
    }
}

public static class DisbursementModule
{
    public static void MapDisbursements(this WebApplication app)
    {
        const string permission="TESORERIA.EGRESO.PREPARAR";
        var group=app.MapGroup("/api/v1/companies/{empresaId:long}/disbursement-drafts");
        group.AddEndpointFilter(async(context,next)=>{
            try{return await next(context);}
            catch(ArgumentException e){return Results.BadRequest(new{error=e.Message});}
            catch(DraftConflict e){return Results.Conflict(new{error=e.Message});}
        });
        group.MapGet("",async(long empresaId,long? antes,DisbursementRepository repo,CancellationToken ct)=>Results.Ok(await repo.ListAsync(empresaId,antes,ct))).RequireErpPermission(permission);
        group.MapGet("/options",async(long empresaId,string? q,long? terceroId,DisbursementRepository repo,CancellationToken ct)=>Results.Ok(await repo.OptionsAsync(empresaId,q,terceroId,ct))).RequireErpPermission(permission);
        group.MapGet("/{id:long}",async(long empresaId,long id,DisbursementRepository repo,CancellationToken ct)=>{
            var result=await repo.GetAsync(empresaId,id,ct);return result is null?Results.NotFound():Results.Ok(result);
        }).RequireErpPermission(permission);
        group.MapPost("",async(long empresaId,DisbursementDraft input,HttpContext http,DisbursementRepository repo,CancellationToken ct)=>Results.Ok(await repo.SaveAsync(empresaId,null,input,Convert.ToInt64(http.Items["UsuarioId"]),ct))).RequireErpPermission(permission);
        group.MapPut("/{id:long}",async(long empresaId,long id,DisbursementDraft input,HttpContext http,DisbursementRepository repo,CancellationToken ct)=>Results.Ok(await repo.SaveAsync(empresaId,id,input,Convert.ToInt64(http.Items["UsuarioId"]),ct))).RequireErpPermission(permission);
    }
}
