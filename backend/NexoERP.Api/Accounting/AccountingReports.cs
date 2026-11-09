using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Security;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Accounting;

public sealed record AccountingReportResult(string Tipo,string Titulo,DateOnly Desde,DateOnly Hasta,
    string[] Columnas,List<object?[]> Filas,bool Truncado,DateTime GeneradoEnUtc);

public sealed class AccountingReports(TenantConnectionFactory connections,ZeusConnectionStore zeusConnections,ZeusRepository zeusRepository)
{
    public const string Permission="CONTABILIDAD.INFORMES.CONSULTAR";
    private const int MaxRows=20000;
    private const string BaseSql="""
        WITH Base AS (
          SELECT CONVERT(date,m.FECHATRA) Fecha,RTRIM(ISNULL(f.DESFUENTE,'')) Tipo,
            RTRIM(m.IDFUENTE) Fuente,RTRIM(m.NUMDOCTRA) Documento,
            RTRIM(ISNULL(m.REFEFAC,'')) Referencia,RTRIM(m.CODICTA) Cuenta,
            RTRIM(COALESCE(a.DESCCTA,m.CODICTA)) NombreCuenta,
            RTRIM(ISNULL(m.DESCRITRA,'')) Descripcion,RTRIM(ISNULL(m.IDCENCO,'')) CentroCosto,
            CASE WHEN m.VALORTRA>0 THEN m.VALORTRA ELSE 0 END Debito,
            CASE WHEN m.VALORTRA<0 THEN -m.VALORTRA ELSE 0 END Credito,
            RTRIM(ISNULL(m.NITTRA,'')) Nit,RTRIM(ISNULL(t.NOMBRETER,'')) Tercero
          FROM dbo.TRANSAC m
          LEFT JOIN dbo.MAECONT a ON a.CODICTA=m.CODICTA
          LEFT JOIN dbo.FUENTES f ON f.IDFUENTE=m.IDFUENTE
          LEFT JOIN dbo.TERCEROS t ON t.IDTERCERO=m.NITTRA
          WHERE m.STATUSTRA IN('AC','XA') AND m.FECHATRA<DATEADD(day,1,@Hasta)
            AND (@Cuenta='' OR m.CODICTA LIKE @Cuenta+'%')
            AND (@Centro='' OR m.IDCENCO=@Centro)
            AND (@Tercero='' OR m.NITTRA LIKE @Tercero+'%' OR t.NOMBRETER LIKE '%'+@Tercero+'%')
        )
        """;

    public async Task<AccountingReportResult> GetAsync(long company,string kind,DateOnly from,DateOnly to,
        string? account,string? thirdParty,string? costCenter,CancellationToken ct)
    {
        if(from>to||from.Year<2000||to.Year>2100||to.DayNumber-from.DayNumber>3660)
            throw new ArgumentException("Selecciona fechas válidas dentro de un período máximo de diez años.");
        account=(account??"").Trim();thirdParty=(thirdParty??"").Trim();costCenter=(costCenter??"").Trim();
        if(account.Length>30||thirdParty.Length>100||costCenter.Length>50)
            throw new ArgumentException("Uno de los filtros excede la longitud permitida.");
        if(kind=="mayor"&&account.Length==0)throw new ArgumentException("Para el libro mayor selecciona una cuenta o prefijo de cuenta.");
        var (title,sql)=kind switch
        {
            "balance"=>("Balance de prueba · Zeus",BalanceSql("1,2,3,4,5,6,7,8,9")),
            "situacion"=>("Situación financiera · Zeus",BalanceSql("1,2,3")),
            "resultados"=>("Resultados del período · Zeus",BalanceSql("4,5,6,7")),
            "patrimonio"=>("Movimientos de patrimonio · Zeus",BalanceSql("3")),
            "efectivo"=>("Efectivo y bancos · Zeus",BalanceSql("11")),
            "diario"=>("Libro diario",DetailSql),
            "mayor"=>("Libro mayor por cuenta",DetailSql),
            "terceros"=>("Auxiliar por tercero",ThirdPartySql),
            "impuestos"=>("Impuestos y retenciones por tercero",TaxSql),
            "centros"=>("Movimientos por centro de costo",CostCenterSql),
            "comprobantes"=>("Relación de comprobantes",DocumentSql),
            "cuentas"=>("Cuentas usadas en los asientos",AccountsSql),
            "cxc"=>("Cartera vigente de clientes · Zeus",PortfolioSql(false)),
            "cxp"=>("Cartera vigente de proveedores · Zeus",PortfolioSql(true)),
            "inventario"=>("Inventario Nexo valorizado al corte",string.Empty),
            _=>throw new ArgumentException("Selecciona un informe contable válido.")
        };
        var operational=kind=="inventario";
        SqlConnection connection;
        if(operational)connection=await connections.OpenAsync(company,false,ct);
        else
        {
            var secret=await zeusConnections.ResolveAsync(company,ct);
            if(string.IsNullOrWhiteSpace(secret))throw new ArgumentException("Configura la conexión Zeus de esta empresa para consultar informes contables.");
            var builder=new SqlConnectionStringBuilder(secret){ApplicationName="NexoERP.Informes.Zeus",ConnectTimeout=15,Enlist=false};
            var settings=(await zeusRepository.SettingsAsync(company,ct))?.Configuracion;
            if(settings is null||!string.Equals(builder.DataSource,settings.ServidorEsperado,StringComparison.OrdinalIgnoreCase)
                ||!string.Equals(builder.InitialCatalog,settings.BaseEsperada,StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("La conexión Zeus no coincide con el destino configurado para esta empresa.");
            connection=new SqlConnection(builder.ConnectionString);
            try{await connection.OpenAsync(ct);}catch{await connection.DisposeAsync();throw;}
        }
        await using var ownedConnection=connection;
        await using var command=connection.CreateCommand();command.CommandTimeout=90;
        if(kind=="inventario")
        {
            command.CommandType=CommandType.StoredProcedure;command.CommandText="inv.usp_ConsultarInventarioAFecha";
            command.Parameters.Add("@EmpresaId",SqlDbType.BigInt).Value=company;
            command.Parameters.Add("@FechaCorte",SqlDbType.Date).Value=to.ToDateTime(TimeOnly.MinValue);
            command.Parameters.Add("@BodegaId",SqlDbType.BigInt).Value=DBNull.Value;
            command.Parameters.Add("@ArticuloId",SqlDbType.BigInt).Value=DBNull.Value;
        }
        else
        {
        command.CommandText=(operational||kind is "cxc" or "cxp"?"":BaseSql)+sql;
        command.Parameters.Add("@E",SqlDbType.BigInt).Value=company;
        command.Parameters.Add("@Desde",SqlDbType.Date).Value=from.ToDateTime(TimeOnly.MinValue);
        command.Parameters.Add("@Hasta",SqlDbType.Date).Value=to.ToDateTime(TimeOnly.MinValue);
        command.Parameters.Add("@Cuenta",SqlDbType.VarChar,30).Value=account;
        command.Parameters.Add("@Tercero",SqlDbType.NVarChar,100).Value=thirdParty;
        command.Parameters.Add("@Centro",SqlDbType.VarChar,50).Value=costCenter;
        }
        await using var reader=await command.ExecuteReaderAsync(ct);
        var columns=Enumerable.Range(0,reader.FieldCount).Select(reader.GetName).ToArray();
        var rows=new List<object?[]>();
        while(rows.Count<=MaxRows&&await reader.ReadAsync(ct))
        {
            var row=new object?[reader.FieldCount];
            for(var i=0;i<row.Length;i++)row[i]=reader.IsDBNull(i)?null:reader.GetValue(i) is string value?value.Trim():reader.GetValue(i);
            rows.Add(row);
        }
        var truncated=rows.Count>MaxRows;if(truncated)rows.RemoveAt(rows.Count-1);
        return new(kind,title,from,to,columns,rows,truncated,DateTime.UtcNow);
    }

    private static string BalanceSql(string classes)
    {
        var predicate=classes=="11"?"Cuenta LIKE '11%'":$"LEFT(Cuenta,1) IN ({string.Join(',',classes.Split(',').Select(x=>"'"+x+"'"))})";
        var period=classes=="4,5,6,7"?"AND Fecha>=@Desde":"";
        return $"""
            SELECT TOP (20001) Cuenta,MAX(NombreCuenta) Nombre,
              CONVERT(decimal(20,2),SUM(CASE WHEN Fecha<@Desde THEN Debito-Credito ELSE 0 END)) [Saldo inicial],
              CONVERT(decimal(20,2),SUM(CASE WHEN Fecha>=@Desde THEN Debito ELSE 0 END)) Debitos,
              CONVERT(decimal(20,2),SUM(CASE WHEN Fecha>=@Desde THEN Credito ELSE 0 END)) Creditos,
              CONVERT(decimal(20,2),SUM(Debito-Credito)) [Saldo final]
            FROM Base WHERE {predicate} {period}
            GROUP BY Cuenta HAVING SUM(Debito)<>0 OR SUM(Credito)<>0
            ORDER BY Cuenta;
            """;
    }

    private const string DetailSql="""
        SELECT TOP (20001) Fecha,Tipo,Fuente,Documento,Referencia,Cuenta,NombreCuenta Nombre,
          Nit,Tercero,CentroCosto Centro,Descripcion,Debito,Credito
        FROM Base WHERE Fecha>=@Desde
        ORDER BY Fecha,Fuente,Documento,Cuenta;
        """;
    private const string ThirdPartySql="""
        SELECT TOP (20001) Nit,Tercero,Cuenta,MAX(NombreCuenta) Nombre,
          CONVERT(decimal(20,2),SUM(Debito)) Debitos,CONVERT(decimal(20,2),SUM(Credito)) Creditos,
          CONVERT(decimal(20,2),SUM(Debito-Credito)) Saldo
        FROM Base WHERE Fecha>=@Desde AND NULLIF(Nit,'') IS NOT NULL
        GROUP BY Nit,Tercero,Cuenta ORDER BY Tercero,Nit,Cuenta;
        """;
    private const string TaxSql="""
        SELECT TOP (20001) Cuenta,MAX(NombreCuenta) Nombre,Nit,Tercero,
          CONVERT(decimal(20,2),SUM(Debito)) Debitos,CONVERT(decimal(20,2),SUM(Credito)) Creditos,
          CONVERT(decimal(20,2),SUM(Debito-Credito)) Saldo
        FROM Base WHERE Fecha>=@Desde AND (Cuenta LIKE '1355%' OR Cuenta LIKE '2365%' OR Cuenta LIKE '2367%' OR Cuenta LIKE '2368%' OR Cuenta LIKE '2408%')
        GROUP BY Cuenta,Nit,Tercero ORDER BY Cuenta,Nit;
        """;
    private const string CostCenterSql="""
        SELECT TOP (20001) CentroCosto Centro,Cuenta,MAX(NombreCuenta) Nombre,
          CONVERT(decimal(20,2),SUM(Debito)) Debitos,CONVERT(decimal(20,2),SUM(Credito)) Creditos,
          CONVERT(decimal(20,2),SUM(Debito-Credito)) Saldo
        FROM Base WHERE Fecha>=@Desde AND NULLIF(CentroCosto,'') IS NOT NULL
        GROUP BY CentroCosto,Cuenta ORDER BY CentroCosto,Cuenta;
        """;
    private const string DocumentSql="""
        SELECT TOP (20001) Fecha,Tipo,Fuente,Documento,Referencia,Nit,Tercero,
          CONVERT(decimal(20,2),SUM(Debito)) Debitos,CONVERT(decimal(20,2),SUM(Credito)) Creditos,
          CONVERT(decimal(20,2),SUM(Debito-Credito)) Diferencia
        FROM Base WHERE Fecha>=@Desde
        GROUP BY Fecha,Tipo,Fuente,Documento,Referencia,Nit,Tercero
        ORDER BY Fecha,Tipo,Documento;
        """;
    private const string AccountsSql="""
        SELECT TOP (20001) Cuenta,MAX(NombreCuenta) Nombre,
          CONVERT(decimal(20,2),SUM(Debito)) Debitos,CONVERT(decimal(20,2),SUM(Credito)) Creditos
        FROM Base WHERE Fecha>=@Desde
        GROUP BY Cuenta ORDER BY Cuenta;
        """;
    private static string PortfolioSql(bool suppliers)
    {
        var party=suppliers?"PROVEEDORES":"CLIENTES";
        var name=suppliers?"Proveedor":"Cliente";
        var id=suppliers?"IDPROVE":"IDCLIENTE";
        var prefix=suppliers?"22":"13";
        var sign=suppliers?"-":"";
        return $"""
            WITH Vigente AS (
              SELECT f.*,ROW_NUMBER() OVER(PARTITION BY f.BU,f.CODICTA,f.IDUNIDAD,f.IDCLIPRV,
                  f.TIPOFACT,f.NUMEFAC,f.VENCFAC,f.REFEFAC ORDER BY f.ANOMESFAC DESC) Fila
              FROM dbo.FACTURAS_BU f
              WHERE f.CODICTA LIKE '{prefix}%'
                AND (@Cuenta='' OR f.CODICTA LIKE @Cuenta+'%')
            )
            SELECT TOP (20001) RTRIM(f.NUMEFAC) Factura,RTRIM(COALESCE(t.IDTERCERO,p.IDTERCERO,f.IDCLIPRV)) Nit,
              RTRIM(COALESCE(t.NOMBRETER,p.RAZONCIAL,f.IDCLIPRV)) {name},RTRIM(f.CODICTA) Cuenta,
              RTRIM(f.TIPOFACT) Tipo,RTRIM(f.BU) Unidad,RTRIM(f.REFEFAC) Referencia,
              REPLACE(RTRIM(f.VENCFAC),'/','-') Vencimiento,
              RTRIM(f.ANOMESFAC) [Último período],
              COALESCE(NULLIF(RTRIM(a.IDMONEDA),''),'COP') Moneda,
              CONVERT(decimal(20,2),{sign}f.SACTFAC) [Saldo actual],
              CASE WHEN ISDATE(f.VENCFAC)=1 AND REPLACE(f.VENCFAC,'-','/')<CONVERT(char(10),GETDATE(),111)
                   THEN 'VENCIDA' ELSE 'PENDIENTE' END Estado
            FROM Vigente f
            LEFT JOIN dbo.{party} p ON p.{id}=f.IDCLIPRV
            LEFT JOIN dbo.TERCEROS t ON t.IDTERCERO=p.IDTERCERO
            JOIN dbo.MAECONT a ON a.CODICTA=f.CODICTA
            WHERE f.Fila=1 AND {sign}f.SACTFAC>0
              AND (@Tercero='' OR p.IDTERCERO LIKE @Tercero+'%' OR p.RAZONCIAL LIKE '%'+@Tercero+'%'
                   OR t.NOMBRETER LIKE '%'+@Tercero+'%')
            ORDER BY {name},Factura,Vencimiento,Cuenta,Unidad,Referencia;
            """;
    }
}

public static class AccountingReportsModule
{
    public static void MapAccountingReports(this WebApplication app)
    {
        app.MapGet("/api/v1/companies/{empresaId:long}/accounting-reports/{tipo}",async(
            long empresaId,string tipo,DateOnly? desde,DateOnly? hasta,string? cuenta,string? tercero,string? centro,
            AccountingReports reports,CancellationToken ct)=>
        {
            try
            {
                var end=hasta??DateOnly.FromDateTime(DateTime.Today);
                var start=desde??new DateOnly(end.Year,end.Month,1);
                return Results.Ok(await reports.GetAsync(empresaId,tipo,start,end,cuenta,tercero,centro,ct));
            }
            catch(ArgumentException error){return Results.BadRequest(new{error=error.Message});}
            catch(SqlException){return Results.Json(new{error="No se pudo consultar el libro contable de Zeus. Revisa la conexión de la empresa y vuelve a intentar."},statusCode:502);}
        }).RequireErpPermission(AccountingReports.Permission);
    }
}
