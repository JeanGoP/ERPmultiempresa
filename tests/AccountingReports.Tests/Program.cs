using System.Data;
using System.Reflection;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Accounting;

var testConnection=Environment.GetEnvironmentVariable("NEXO_ACCOUNTING_TEST_CONNECTION")
    ?? "Server=(localdb)\\MSSQLLocalDB;Database=master;Integrated Security=True;TrustServerCertificate=True";
{
    await using var connection=new SqlConnection(testConnection);
    await connection.OpenAsync();
    await using var command=connection.CreateCommand();
    command.CommandText="""
        CREATE TABLE #TRANSAC(IDFUENTE char(2),NUMDOCTRA char(10),FECHATRA datetime,CODICTA char(16),VALORTRA decimal(18,2),
          REFEFAC varchar(20),DESCRITRA varchar(100),IDCENCO char(8),NITTRA char(15),STATUSTRA char(2));
        CREATE TABLE #MAECONT(CODICTA char(16),DESCCTA varchar(40));
        CREATE TABLE #FUENTES(IDFUENTE char(2),DESFUENTE varchar(40));
        CREATE TABLE #TERCEROS(IDTERCERO char(15),NOMBRETER varchar(60));
        INSERT #MAECONT VALUES('110505','Caja'),('4135','Ingresos');
        INSERT #FUENTES VALUES('09','Notas'),('21','Factura');
        INSERT #TERCEROS VALUES('9001','Tercero anterior');
        INSERT #TRANSAC VALUES
          ('09','0000000001','2020-01-01','110505',100,'','Histórico','01','9001','AC'),
          ('09','0000000001','2020-01-01','4135',-100,'','Histórico','01','9001','AC'),
          ('21','0000000002','2026-06-01','110505',50,'','Nexo','01','9001','XA'),
          ('21','0000000002','2026-06-01','4135',-50,'','Nexo','01','9001','XA'),
          ('21','0000000003','2026-06-02','110505',500,'','No vigente','01','9001','AN');
        """;
    await command.ExecuteNonQueryAsync();
    var type=typeof(AccountingReports);
    var baseSql=(string)type.GetField("BaseSql",BindingFlags.NonPublic|BindingFlags.Static)!.GetRawConstantValue()!;
    var balanceSql=(string)type.GetMethod("BalanceSql",BindingFlags.NonPublic|BindingFlags.Static)!.Invoke(null,["1,2,3,4,5,6,7,8,9"])!;
    command.CommandText=(baseSql+balanceSql).Replace("dbo.TRANSAC","#TRANSAC",StringComparison.Ordinal)
        .Replace("dbo.MAECONT","#MAECONT",StringComparison.Ordinal)
        .Replace("dbo.FUENTES","#FUENTES",StringComparison.Ordinal)
        .Replace("dbo.TERCEROS","#TERCEROS",StringComparison.Ordinal);
    command.Parameters.Add("@Hasta",SqlDbType.Date).Value=new DateTime(2026,12,31);
    command.Parameters.Add("@Desde",SqlDbType.Date).Value=new DateTime(2026,1,1);
    command.Parameters.Add("@Cuenta",SqlDbType.VarChar,30).Value="";
    command.Parameters.Add("@Centro",SqlDbType.VarChar,50).Value="";
    command.Parameters.Add("@Tercero",SqlDbType.NVarChar,100).Value="";
    var result=new Dictionary<string,(decimal initial,decimal debits,decimal credits,decimal final)>();
    await using(var reader=await command.ExecuteReaderAsync())
        while(await reader.ReadAsync())result.Add(reader.GetString(0).Trim(),(reader.GetDecimal(2),reader.GetDecimal(3),reader.GetDecimal(4),reader.GetDecimal(5)));
    if(result.Count!=2||result["110505"]!=(100m,50m,0m,150m)||result["4135"]!=(-100m,0m,50m,-150m))
        throw new Exception("El balance no incluyó el histórico Zeus, duplicó Nexo o incluyó un movimiento anulado.");
    foreach(var queryName in new[]{"DetailSql","ThirdPartySql","TaxSql","CostCenterSql","DocumentSql","AccountsSql"})
    {
        command.CommandText=(baseSql+(string)type.GetField(queryName,BindingFlags.NonPublic|BindingFlags.Static)!.GetRawConstantValue()!)
            .Replace("dbo.TRANSAC","#TRANSAC",StringComparison.Ordinal)
            .Replace("dbo.MAECONT","#MAECONT",StringComparison.Ordinal)
            .Replace("dbo.FUENTES","#FUENTES",StringComparison.Ordinal)
            .Replace("dbo.TERCEROS","#TERCEROS",StringComparison.Ordinal);
        await using var reader=await command.ExecuteReaderAsync();
        while(await reader.ReadAsync()){}
    }
    Console.WriteLine("Informes Zeus: histórico, asiento Nexo, saldos iniciales y exclusión de anulado correctos.");
}
