using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Globalization;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Zeus;

public sealed class ZeusRepository(TenantConnectionFactory connections)
{
    private sealed class CanonicalDecimal : JsonConverter<decimal>
    {
        public override decimal Read(ref Utf8JsonReader reader,Type type,JsonSerializerOptions options)=>reader.GetDecimal();
        public override void Write(Utf8JsonWriter writer,decimal value,JsonSerializerOptions options)
            =>writer.WriteRawValue(value.ToString("G29",CultureInfo.InvariantCulture));
    }
    private static readonly JsonSerializerOptions SnapshotOptions=new() { Converters={new CanonicalDecimal()} };
    private static string SerializeSnapshot(ZeusSnapshot snapshot)=>JsonSerializer.Serialize(snapshot,SnapshotOptions);
    internal static SqlCommand Command(SqlConnection c, string sql, long company, SqlTransaction? tx=null)
    {
        var q=c.CreateCommand(); q.Transaction=tx; q.CommandText=sql;
        q.Parameters.Add("@E",SqlDbType.BigInt).Value=company;
        return q;
    }
    internal static void Add(SqlCommand q,string name,object value)=>q.Parameters.AddWithValue(name,value);
    public async Task<ZeusSettingsRequest?> SettingsAsync(long company,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=Command(c,"SELECT Version,Configuracion FROM core.ZeusConfiguracion WHERE EmpresaId=@E",company);
        await using var r=await q.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct)?new(r.GetInt32(0),JsonSerializer.Deserialize<ZeusSettings>(r.GetString(1))!):null;
    }
    public async Task SaveSettingsAsync(long company,long user,ZeusSettingsRequest input,CancellationToken ct)
    {
        if(input.Configuracion is null) throw new ArgumentException("Falta la configuración.");
        ZeusJournal.Validate(input.Configuracion);
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=Command(c,"""
            IF EXISTS(SELECT 1 FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Estado IN('PENDIENTE','ENVIANDO','INCIERTO'))
                THROW 51701,'Hay envios pendientes o inciertos; resuelvelos antes de cambiar la configuracion.',1;
            DECLARE @VersionActual int;
            SELECT @VersionActual=Version FROM core.ZeusConfiguracion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E;
            IF ISNULL(@VersionActual,0)<>@V THROW 51702,'La configuracion cambio; vuelve a consultarla.',1;
            IF @VersionActual IS NULL
                INSERT core.ZeusConfiguracion(EmpresaId,Configuracion,ActualizadoPor) VALUES(@E,@J,@U);
            ELSE UPDATE core.ZeusConfiguracion SET Configuracion=@J,Version=Version+1,ActualizadoPor=@U,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@E,@U,'ZEUS_CONFIGURAR','core.ZeusConfiguracion',CONVERT(nvarchar(100),@E),@J,'ZEUS');
            """,company,tx);
        Add(q,"@V",input.Version); Add(q,"@U",user); Add(q,"@J",JsonSerializer.Serialize(input.Configuracion));
        await q.ExecuteNonQueryAsync(ct); await tx.CommitAsync(ct);
    }
    private static async Task<ZeusSnapshot> BuildAsync(SqlConnection c,SqlTransaction tx,long company,long receipt,ZeusPreviewRequest input,CancellationToken ct)
    {
        await using var q=Command(c,"SELECT Configuracion FROM core.ZeusConfiguracion WITH(HOLDLOCK) WHERE EmpresaId=@E",company,tx);
        var json=await q.ExecuteScalarAsync(ct) as string ?? throw new ArgumentException("Configura primero la integración de esta empresa.");
        var settings=JsonSerializer.Deserialize<ZeusSettings>(json)!;
        q.CommandText="""
            SELECT r.TerceroId,d.NumeroDocumento,r.FechaContable,d.FechaDocumento,COALESCE(d.FechaVencimiento,d.FechaDocumento),
                d.TotalPagar,d.ImpuestoTotal,d.Moneda,d.CargoTotal,d.DocumentoProveedorId
            FROM inv.RecepcionMercancia r WITH(HOLDLOCK)
            JOIN comp.DocumentoProveedor d WITH(HOLDLOCK) ON d.EmpresaId=r.EmpresaId AND d.DocumentoProveedorId=r.DocumentoProveedorId
            WHERE r.EmpresaId=@E AND r.RecepcionMercanciaId=@R AND r.Estado='CONTABILIZADA' AND d.Estado='CONTABILIZADO';
            """;
        Add(q,"@R",receipt);
        long supplier,document; string invoice; DateTime date,issued,due; decimal total,taxes;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)) throw new ArgumentException("La entrada y la factura deben estar contabilizadas en esta empresa.");
            supplier=r.GetInt64(0);invoice=r.GetString(1);date=r.GetDateTime(2);issued=r.GetDateTime(3);due=r.GetDateTime(4);
            total=r.GetDecimal(5);taxes=r.GetDecimal(6);document=r.GetInt64(9);
            if(r.GetString(7).Trim()!="COP" || r.GetDecimal(8)!=0)
                throw new ArgumentException("Esta versión exige COP y facturas sin cargos globales; se requiere distribución contable explícita para otros casos.");
        }
        q.CommandText="""
            SELECT l.ArticuloId,l.TotalNeto,l.Retencion,l.Clasificacion,l.Cargo,
              (SELECT COUNT(*) FROM inv.RecepcionMercanciaLinea rl WHERE rl.EmpresaId=l.EmpresaId AND rl.RecepcionMercanciaId=@R AND rl.DocumentoProveedorLineaId=l.DocumentoProveedorLineaId)
            FROM comp.DocumentoProveedorLinea l WITH(HOLDLOCK) WHERE l.EmpresaId=@E AND l.DocumentoProveedorId=@D ORDER BY l.NumeroLinea;
            """;
        Add(q,"@D",document);
        var lines=new List<ZeusSourceLine>(); decimal withholding=0;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            while(await r.ReadAsync(ct))
            {
                if(r.IsDBNull(0) || r.GetString(3)!="INVENTARIO" || r.GetDecimal(4)!=0 || r.GetInt32(5)!=1)
                    throw new ArgumentException("Solo se admiten facturas completas de mercancía, sin servicios ni cargos por distribuir.");
                lines.Add(new(r.GetInt64(0),r.GetDecimal(1))); withholding+=r.GetDecimal(2);
            }
        }
        if(lines.Count==0 || lines.Count>1000) throw new ArgumentException("La entrada debe tener entre 1 y 1000 líneas.");
        return ZeusJournal.Build(settings,new(receipt,supplier,invoice,date,issued,due,total,taxes,withholding,lines.ToArray()),input);
    }
    public static string Fingerprint(ZeusSnapshot snapshot)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(SerializeSnapshot(snapshot))));
    public async Task<object> PreviewAsync(long company,long receipt,ZeusPreviewRequest input,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        var result=await BuildAsync(c,tx,company,receipt,input,ct);
        await tx.CommitAsync(ct);
        return new { huella=Fingerprint(result),comprobante=result,debito=result.Movimientos.Where(l=>l.Valor>0).Sum(l=>l.Valor),credito=-result.Movimientos.Where(l=>l.Valor<0).Sum(l=>l.Valor),validadoEnZeus=false };
    }
    public async Task<long> ApproveAsync(long company,long receipt,long user,ZeusApproveRequest input,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        var snapshot=await BuildAsync(c,tx,company,receipt,new(input.Impuestos,input.Retenciones),ct);
        if(!snapshot.Configuracion.Habilitado) throw new ArgumentException("El envío a Zeus está desactivado para esta empresa.");
        if(input.Huella!=Fingerprint(snapshot)) throw new ArgumentException("La vista previa cambió; revísala y aprueba su nueva huella.");
        await using var q=Command(c,"""
            DECLARE @Id bigint,@Estado varchar(25),@Anterior nvarchar(max);
            SELECT @Id=ZeusEnvioId,@Estado=Estado,@Anterior=Snapshot FROM core.ZeusEnvio WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND RecepcionMercanciaId=@R;
            IF @Estado IN('PENDIENTE','ENVIANDO','CONTABILIZADO')
            BEGIN
                IF @Anterior<>@J THROW 51703,'La entrada ya tiene un envio con otro comprobante.',1;
                SELECT @Id; RETURN;
            END;
            IF @Estado='INCIERTO' THROW 51704,'Resultado incierto: requiere conciliacion con Zeus, no se permite reenviar.',1;
            IF @Id IS NULL
            BEGIN
                INSERT core.ZeusEnvio(EmpresaId,RecepcionMercanciaId) VALUES(@E,@R);
                SET @Id=SCOPE_IDENTITY();
            END;
            UPDATE core.ZeusEnvio SET Estado='PENDIENTE',Snapshot=@J,AprobadoPor=@U,Error=NULL,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND ZeusEnvioId=@Id;
            INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
            VALUES(@E,@U,'ZEUS_APROBAR','core.ZeusEnvio',CONVERT(nvarchar(100),@Id),@J,'ZEUS');
            SELECT @Id;
            """,company,tx);
        Add(q,"@R",receipt);Add(q,"@J",SerializeSnapshot(snapshot));Add(q,"@U",user);
        var id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));await tx.CommitAsync(ct);return id;
    }
    public async Task<object> ListAsync(long company,string? state,int offset,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=Command(c,"""
            SELECT ZeusEnvioId,RecepcionMercanciaId,Clave,Estado,Intentos,Fuente,Documento,Error,CreadoEnUtc,ActualizadoEnUtc
            FROM core.ZeusEnvio WHERE EmpresaId=@E AND (@S IS NULL OR Estado=@S)
            ORDER BY ZeusEnvioId DESC OFFSET @O ROWS FETCH NEXT 100 ROWS ONLY;
            """,company);
        Add(q,"@S",(object?)state??DBNull.Value);Add(q,"@O",Math.Max(0,offset));
        var rows=new List<Dictionary<string,object?>>(); await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct)) { var row=new Dictionary<string,object?>(); for(int i=0;i<r.FieldCount;i++) row[r.GetName(i)]=r.IsDBNull(i)?null:r.GetValue(i);rows.Add(row); }
        return rows;
    }
    internal async Task<(long Id,long Company,Guid Key,ZeusSnapshot Snapshot)?> ClaimAsync(CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(null,true,ct);
        await using var q=c.CreateCommand();q.CommandText="""
            SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
            UPDATE core.ZeusEnvio SET Estado='INCIERTO',Error=N'El proceso fue interrumpido. Conciliar antes de reenviar.',ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE Estado='ENVIANDO' AND ActualizadoEnUtc<DATEADD(minute,-15,SYSUTCDATETIME());
            ;WITH nextJob AS(SELECT TOP(1) * FROM core.ZeusEnvio WITH(UPDLOCK,READPAST,READCOMMITTEDLOCK) WHERE Estado='PENDIENTE' ORDER BY ZeusEnvioId)
            UPDATE nextJob SET Estado='ENVIANDO',Intentos=Intentos+1,ActualizadoEnUtc=SYSUTCDATETIME()
            OUTPUT inserted.ZeusEnvioId,inserted.EmpresaId,inserted.Clave,inserted.Snapshot;
            """;
        await using var r=await q.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct)?(r.GetInt64(0),r.GetInt64(1),r.GetGuid(2),JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(3))!):null;
    }
    internal async Task FinishAsync(long company,long id,string state,string? source,string? document,string? error,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=Command(c,"""
            SET XACT_ABORT ON; BEGIN TRANSACTION;
            UPDATE core.ZeusEnvio SET Estado=@S,Fuente=@F,Documento=@D,Error=@Error,ActualizadoEnUtc=SYSUTCDATETIME()
            WHERE EmpresaId=@E AND ZeusEnvioId=@Id AND Estado IN('ENVIANDO','INCIERTO');
            IF @@ROWCOUNT=1
                INSERT audit.Evento(EmpresaId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
                VALUES(@E,'ZEUS_RESULTADO','core.ZeusEnvio',CONVERT(nvarchar(100),@Id),
                    (SELECT @S estado,@F fuente,@D documento,@Error error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'ZEUS');
            COMMIT;
            """,company);
        Add(q,"@Id",id);Add(q,"@S",state);Add(q,"@F",(object?)source??DBNull.Value);Add(q,"@D",(object?)document??DBNull.Value);Add(q,"@Error",(object?)error??DBNull.Value);
        await q.ExecuteNonQueryAsync(ct);
    }
    internal async Task<bool> EligibleAsync(long company,ZeusSnapshot expected,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        var taxes=expected.Movimientos.Where(m=>m.Regla.Concepto is "IVA" or "OTRO_IMPUESTO")
            .Select(m=>new ZeusTax(m.Regla.Concepto,m.Tarifa,Math.Abs(m.Base),Math.Abs(m.Valor))).ToArray();
        var withholdings=expected.Movimientos.Where(m=>m.Regla.Concepto is "RETEFUENTE" or "RETEIVA" or "RETEICA")
            .Select(m=>new ZeusTax(m.Regla.Concepto,m.Tarifa,Math.Abs(m.Base),Math.Abs(m.Valor))).ToArray();
        try
        {
            var current=await BuildAsync(c,tx,company,expected.Origen.RecepcionId,new(taxes,withholdings),ct);
            await tx.CommitAsync(ct);return Fingerprint(current)==Fingerprint(expected);
        }
        catch(ArgumentException) { return false; }
    }
    internal async Task<(Guid Key,ZeusSnapshot Snapshot)> UncertainAsync(long company,long id,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=Command(c,"SELECT Clave,Snapshot FROM core.ZeusEnvio WHERE EmpresaId=@E AND ZeusEnvioId=@Id AND Estado='INCIERTO'",company);
        Add(q,"@Id",id);await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct)) throw new ArgumentException("No existe un envío incierto con ese identificador en esta empresa.");
        return (r.GetGuid(0),JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(1))!);
    }
}
