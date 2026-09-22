using System.Data;
using System.Xml.Linq;
using Microsoft.Data.SqlClient;

namespace NexoERP.Api.Zeus;

public sealed record ZeusResult(string Estado,string? Fuente=null,string? Documento=null,string? Error=null);
public sealed partial class ZeusTransport(IConfiguration configuration)
{
    private async Task<SqlConnection> OpenAsync(long company,ZeusSettings settings,CancellationToken ct)
    {
        // La clave depende de EmpresaId, no de un alias suministrado por el navegador.
        var secret=configuration[$"Zeus:Companies:{company}:ConnectionString"];
        if(string.IsNullOrWhiteSpace(secret)) throw new ArgumentException("Falta la conexión privada de Zeus para esta empresa.");
        SqlConnectionStringBuilder builder;
        try {builder=new SqlConnectionStringBuilder(secret);}
        catch(ArgumentException){throw new ArgumentException("La conexión privada de Zeus tiene un formato inválido. Revisar con soporte.");}
        if(!string.Equals(builder.DataSource,settings.ServidorEsperado,StringComparison.OrdinalIgnoreCase)
           || !string.Equals(builder.InitialCatalog,settings.BaseEsperada,StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("La conexión privada no coincide con el destino configurado para esta empresa.");
        builder.ConnectTimeout=15;builder.ApplicationName="NexoERP.Zeus";builder.Enlist=false;
        var c=new SqlConnection(builder.ConnectionString);
        try { await c.OpenAsync(ct);return c; } catch { await c.DisposeAsync();throw; }
    }
    public async Task<object> CheckAsync(long company,ZeusSettings settings,CancellationToken ct)
    {
        await using var c=await OpenAsync(company,settings,ct);
        await using var q=c.CreateCommand();q.CommandText="SELECT DB_NAME(), CASE WHEN OBJECT_ID('dbo.spWSG_Contabilidad','P') IS NOT NULL AND OBJECT_ID('dbo.DOCUMENT','U') IS NOT NULL AND OBJECT_ID('dbo.TRANSAC','U') IS NOT NULL THEN 1 ELSE 0 END";
        await using var r=await q.ExecuteReaderAsync(ct);await r.ReadAsync(ct);
        return new { conectado=true,baseDatos=r.GetString(0),contratoDisponible=r.GetInt32(1)==1,contabilizacionProbada=false };
    }
    private static async Task<string?> VerifyAsync(SqlConnection c,SqlTransaction? tx,ZeusSnapshot s,Guid key,CancellationToken ct)
    {
        await using var q=c.CreateCommand();q.Transaction=tx;
        q.CommandText="""
            SELECT NUMEDCTO,FECHDCTO,SUDBDCTO,SUCRDCTO FROM dbo.DOCUMENT
            WHERE FNTEDCTO=@F AND (DESCDCTO=@M OR CONVERT(nvarchar(max),XmlAdicionales)=@M);
            """;
        q.Parameters.Add("@F",SqlDbType.VarChar,2).Value=s.Configuracion.Fuente;
        q.Parameters.Add("@M",SqlDbType.VarChar,120).Value=ZeusXml.Marker(key);
        string number;var debit=s.Movimientos.Where(m=>m.Valor>0).Sum(m=>m.Valor);
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)) return null;
            number=r.GetString(0).Trim();
            if(Convert.ToString(r.GetValue(1))?.Replace("/","")!=s.Origen.FechaContable.ToString("yyyyMMdd")
               || Convert.ToDecimal(r.GetValue(2))!=debit || Convert.ToDecimal(r.GetValue(3))!=debit)
                throw new InvalidOperationException("El comprobante encontrado no coincide con las fechas o totales esperados.");
            if(await r.ReadAsync(ct)) throw new InvalidOperationException("Hay más de un comprobante con la misma clave de integración.");
        }
        q.CommandText="""
            SELECT RTRIM(CODICTA),CASE WHEN VALORTRA>0 THEN 1 ELSE -1 END,SUM(VALORTRA)
            FROM dbo.TRANSAC WHERE IDFUENTE=@F AND NUMDOCTRA=@N AND STATUSTRA IN('AC','XA') AND BU=@B
            GROUP BY CODICTA,CASE WHEN VALORTRA>0 THEN 1 ELSE -1 END;
            """;
        q.Parameters.Add("@N",SqlDbType.VarChar,10).Value=number;
        q.Parameters.Add("@B",SqlDbType.VarChar,20).Value=s.Configuracion.UnidadNegocio;
        var expected=s.Movimientos.GroupBy(m=>(m.Regla.Cuenta,Math.Sign(m.Valor))).ToDictionary(g=>g.Key,g=>g.Sum(m=>m.Valor));
        await using(var r=await q.ExecuteReaderAsync(ct))
            while(await r.ReadAsync(ct))
                if(!expected.Remove((r.GetString(0),r.GetInt32(1)),out var amount) || amount!=Convert.ToDecimal(r.GetValue(2)))
                    throw new InvalidOperationException("Los movimientos encontrados no coinciden con las cuentas e importes aprobados.");
        if(expected.Count!=0) throw new InvalidOperationException("Faltan movimientos contables en Zeus.");
        return number;
    }
    public async Task<ZeusResult> ReconcileAsync(long company,ZeusSnapshot s,Guid key,CancellationToken ct)
    {
        await using var c=await OpenAsync(company,s.Configuracion,ct);
        var number=await VerifyAsync(c,null,s,key,ct);
        return number is null ? new("INCIERTO",Error:"No se encontró el comprobante. Esto no autoriza un reenvío; revisar en Zeus.") : new("CONTABILIZADO",s.Configuracion.Fuente,number);
    }
    public async Task<ZeusResult> SendAsync(long company,ZeusSnapshot s,Guid key,CancellationToken ct)
    {
        SqlConnection? c=null;SqlTransaction? tx=null;bool commitStarted=false;
        var stage="conexión con Zeus";
        try
        {
            c=await OpenAsync(company,s.Configuracion,ct);
            stage="inicio de transacción y bloqueo del envío";
            tx=(SqlTransaction)await c.BeginTransactionAsync(ct);
            await using var q=c.CreateCommand();q.Transaction=tx;q.CommandTimeout=90;
            q.CommandText="""
                SET XACT_ABORT ON;
                DECLARE @L int;
                EXEC @L=sys.sp_getapplock @Resource='NexoERP.Zeus.Contabilizar',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
                IF @L<0 THROW 51710,'No fue posible bloquear el envio a Zeus.',1;
                """;
            await q.ExecuteNonQueryAsync(ct);
            stage="comprobación de envío previo";
            var existing=await VerifyAsync(c,tx,s,key,ct);
            if(existing is not null) { await tx.RollbackAsync(CancellationToken.None);return new("CONTABILIZADO",s.Configuracion.Fuente,existing); }
            if(s.Proveedor.CodigoProveedor==s.Proveedor.CodigoTercero)
            {
                stage="validación del tercero y proveedor";
                (bool Third,bool Supplier) master;
                try { master=await SupplierExists(c,tx,s.Proveedor.CodigoProveedor,ct); }
                catch(ArgumentException error) { throw new InvalidOperationException(SafeSupplierDiagnostic(error.Message,c.ConnectionString)); }
                if(!master.Third||!master.Supplier)
                    throw new InvalidOperationException("El tercero o proveedor no existe en Zeus. Envía el proveedor desde el maestro y vuelve a preparar la entrada.");
            }
            stage="validación de cuentas contables";
            q.CommandText="""
                IF EXISTS(SELECT 1 FROM
                    (SELECT n.value('@Cuenta','varchar(20)') Cuenta,n.value('@Proveedor','bit') Proveedor,
                            n.value('@Retencion','bit') Retencion,n.value('@Tarifa','decimal(18,6)') Tarifa
                     FROM @Accounts.nodes('/Cuentas/Cuenta') x(n)) a
                    LEFT JOIN dbo.MAECONT m ON m.CODICTA=a.Cuenta
                    WHERE m.CODICTA IS NULL OR ISNULL(m.HABILITARCTA,0)<>1 OR ISNULL(m.TIPOCTA,'')<>'D'
                       OR (a.Proveedor=1 AND ISNULL(m.INDCPICTA,0)<>3)
                       OR (a.Proveedor=0 AND m.INDCPICTA IN(2,3,6))
                       OR (a.Retencion=1 AND (m.PORCEIMPUESTO IS NULL OR m.PORCEIMPUESTO<>a.Tarifa OR ISNULL(m.IndValorRetenido,0)<>0)))
                    THROW 51711,'Cuenta no habilitada, incompatible o tarifa de retencion distinta a PORCEIMPUESTO en Zeus. Revisa y guarda las cuentas de la empresa.',1;
                """;
            // Zeus puede conservar compatibilidad 100: XML evita depender de OPENJSON (130+).
            q.Parameters.Add("@Accounts",SqlDbType.Xml).Value=new XElement("Cuentas",s.Movimientos
                .Select(m=>(m.Regla.Cuenta,Proveedor:m.Regla.Concepto=="PROVEEDOR",Retencion:ZeusJournal.IsRetention(m.Regla.Concepto),m.Tarifa)).Distinct()
                .Select(a=>new XElement("Cuenta",new XAttribute("Cuenta",a.Cuenta),new XAttribute("Proveedor",a.Proveedor?1:0),new XAttribute("Retencion",a.Retencion?1:0),new XAttribute("Tarifa",a.Tarifa))))
                .ToString(SaveOptions.DisableFormatting);
            await q.ExecuteNonQueryAsync(ct);q.Parameters.Clear();
            stage="dbo.spWSG_Contabilidad";
            q.CommandText="dbo.spWSG_Contabilidad";q.CommandType=CommandType.StoredProcedure;
            q.Parameters.Add("@Iden",SqlDbType.Int).Value=16;
            q.Parameters.Add("@XML",SqlDbType.VarChar,-1).Value=ZeusXml.Build(s,key);
            var returned=q.Parameters.Add("@RETURN_VALUE",SqlDbType.Int);returned.Direction=ParameterDirection.ReturnValue;
            // Consumir todos los resultados: el adaptador original devuelve un SELECT antes de terminar.
            await using(var r=await q.ExecuteReaderAsync(ct))
                do { while(await r.ReadAsync(ct)) { } } while(await r.NextResultAsync(ct));
            if(Convert.ToInt32(returned.Value)!=0) throw new InvalidOperationException($"Zeus devolvió el código de retorno {Convert.ToInt32(returned.Value)}; no se confirmó el comprobante.");
            stage="verificación del comprobante y movimientos creados";
            var number=await VerifyAsync(c,tx,s,key,ct)
                ?? throw new InvalidOperationException("Zeus no creó el comprobante esperado. Se revierte la transacción.");
            stage="confirmación de la transacción";commitStarted=true;await tx.CommitAsync(ct);
            return new("CONTABILIZADO",s.Configuracion.Fuente,number);
        }
        catch(Exception error) when(error is SqlException or InvalidOperationException or ArgumentException or OperationCanceledException)
        {
            var uncertain=commitStarted;
            if(tx is not null && !commitStarted)
            {
                try { await tx.RollbackAsync(CancellationToken.None); }
                catch { uncertain=true; }
            }
            // Conservar el motivo de negocio de RAISERROR/THROW, incluso de procedimientos
            // anidados o errores posteriores a un SELECT. Ocultar secretos antes de truncar.
            string detail;
            if(error is SqlException sql)
            {
                var errors=sql.Errors.Cast<SqlError>().Where(e=>e.Number!=3621).Take(5);
                detail=string.Join(" | ",errors.Select(e=>$"SQL {e.Number} · {(string.IsNullOrWhiteSpace(e.Procedure)?stage:e.Procedure)} · línea {e.LineNumber}: {e.Message}"));
                if(string.IsNullOrWhiteSpace(detail))detail=$"SQL {sql.Number}: {sql.Message}";
            }
            else detail=error is OperationCanceledException?"La operación se interrumpió o excedió su tiempo máximo.":error.Message;
            var message=SafeSupplierDiagnostic($"Etapa: {stage}. {detail}",configuration[$"Zeus:Companies:{company}:ConnectionString"]);
            return new(uncertain?"INCIERTO":"RECHAZADO",Error:message+(uncertain?
                " No se pudo confirmar el resultado; concilia en Zeus antes de cualquier reenvío.":
                tx is null?" No se inició una transacción contable.":" Se revirtió la transacción; no se confirmó la contabilización."));
        }
        finally { if(tx is not null) await tx.DisposeAsync();if(c is not null) await c.DisposeAsync(); }
    }
}
