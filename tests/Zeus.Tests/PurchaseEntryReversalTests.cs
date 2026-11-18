using System.Data;
using System.Globalization;
using System.Xml.Linq;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Zeus;

internal static class PurchaseEntryReversalTests
{
    public static void Run(Action<bool,string> check,Action<Action,string> reject,ZeusSettings settings,ZeusSource source,ZeusPreviewRequest input)
    {
        var original=ZeusJournal.Build(settings,source,input);
        var key=Guid.NewGuid();
        var reverse=ZeusPurchaseEntryReversalPolicy.Build(original,key,settings.Fuente,"0100000001",new(2026,10,1),"Corrección de entrada equivocada");
        check(reverse.Movimientos.Zip(original.Movimientos).All(pair=>pair.First.Valor==-pair.Second.Valor
            &&pair.First.Base==-pair.Second.Base&&pair.First.Tarifa==pair.Second.Tarifa&&pair.First.Regla==pair.Second.Regla),
            "Reversión de entrada invierte valores y bases sin modificar cuentas, dimensiones ni tarifas");
        check(reverse.Origen.Factura==original.Origen.Factura&&reverse.Origen.Vencimiento==original.Origen.Vencimiento
            &&reverse.Configuracion==original.Configuracion&&reverse.Proveedor==original.Proveedor
            &&reverse.Origen.FechaContable==new DateTime(2026,10,1),"Reversión conserva factura, proveedor, vencimiento y fuente originales");
        check(ZeusPurchaseEntryReversalPolicy.Original(reverse).Movimientos.SequenceEqual(original.Movimientos),
            "El comprobante original se reconstruye exactamente desde el reverso congelado");
        var originalXml=XDocument.Parse(ZeusXml.Build(original,key)).Descendants("Transac").ToArray();
        var xml=XDocument.Parse(ZeusXml.Build(reverse,Guid.NewGuid()));
        var lines=xml.Descendants("Transac").ToArray();
        var referenceFields=new[]{"CODICTA","NITTRA","CLIPRV","TIPOFAC","NUMEFAC","VENCEFAC","REFEFAC","BU","IDCENCO","AUXIAUX","IDITEM","CODPRESU","NRESERVA","PORRETETRA","Fechafact"};
        check(lines.Zip(originalXml).All(pair=>referenceFields.All(field=>pair.First.Element(field)?.Value==pair.Second.Element(field)?.Value)
            &&decimal.Parse(pair.First.Element("VALORTRA")!.Value,CultureInfo.InvariantCulture)==-decimal.Parse(pair.Second.Element("VALORTRA")!.Value,CultureInfo.InvariantCulture)
            &&decimal.Parse(pair.First.Element("BASERETETRA")!.Value,CultureInfo.InvariantCulture)==-decimal.Parse(pair.Second.Element("BASERETETRA")!.Value,CultureInfo.InvariantCulture)),
            "XML de reversión mantiene la identidad completa de factura y firma de impuestos");
        check(xml.Descendants("Document").Single().Element("DESCDCTO")!.Value.StartsWith("REVERSIÓN ENTRADA")
            &&lines.Single(line=>line.Element("CODICTA")!.Value=="2205").Element("VALORTRA")!.Value.StartsWith("-")==false,
            "La reversión debita al proveedor y se identifica con su comprobante original");
        reject(()=>ZeusPurchaseEntryReversalPolicy.Build(original,key,settings.Fuente,"0100000001",new(2026,1,1),"Motivo suficientemente largo"),
            "Reversión no admite fecha anterior a la entrada original");
        reject(()=>ZeusPurchaseEntryReversalPolicy.Build(reverse,key,settings.Fuente,"0100000001",new(2026,10,2),"Motivo suficientemente largo"),
            "Una reversión no se utiliza como nueva entrada original");
    }

    public static async Task SqlAsync(ZeusSettings settings,ZeusSource source,ZeusPreviewRequest input,Action<bool,string> check)
    {
        const string server=@"Server=(localdb)\MSSQLLocalDB;Integrated Security=True;TrustServerCertificate=True";
        var database="NexoPurchaseReversalQa_"+Guid.NewGuid().ToString("N");
        await using var admin=new SqlConnection(server+";Database=master");await admin.OpenAsync();
        await using var setup=admin.CreateCommand();setup.CommandText=$"CREATE DATABASE [{database}]";await setup.ExecuteNonQueryAsync();
        try
        {
            var cs=server+";Database="+database;
            await using var connection=new SqlConnection(cs);await connection.OpenAsync();
            await using var command=connection.CreateCommand();
            async Task Run(string sql){command.CommandText=sql;await command.ExecuteNonQueryAsync();}
            async Task<int> Count(){command.CommandText="SELECT COUNT(*) FROM dbo.DOCUMENT";return Convert.ToInt32(await command.ExecuteScalarAsync());}
            await Run("""
                CREATE TABLE dbo.DOCUMENT(FNTEDCTO varchar(2),NUMEDCTO varchar(10),FECHDCTO varchar(10),DESCDCTO nvarchar(120),SUDBDCTO money,SUCRDCTO money,XmlAdicionales nvarchar(120));
                CREATE TABLE dbo.TRANSAC(IDFUENTE varchar(2),NUMDOCTRA varchar(10),ANOTRA varchar(6),FECHATRA varchar(10),
                    CODICTA varchar(20),NITTRA varchar(25),CLIPRV varchar(10),INDCPITRA char(1),TIPOFAC varchar(3),NUMEFAC varchar(15),
                    VENCEFAC varchar(10),REFEFAC varchar(25),BU varchar(25),IDCENCO varchar(16),AUXIAUX varchar(16),IDITEM varchar(16),
                    CODPRESU varchar(16),NRESERVA varchar(16),PORRETETRA decimal(18,4),BASERETETRA money,VALORTRA money,STATUSTRA char(2));
                CREATE TABLE dbo.FACTURAS_BU(BU varchar(25),CODICTA varchar(20),IDUNIDAD char(3),IDCLIPRV varchar(10),
                    TIPOFACT varchar(3),NUMEFAC varchar(15),VENCFAC char(10),REFEFAC varchar(25),ANOMESFAC varchar(6),SACTFAC money);
                CREATE TABLE dbo.PROVEEDORES(IDPROVE varchar(10),IDTERCERO varchar(25));
                CREATE TABLE dbo.MAECONT(CODICTA varchar(20),HABILITARCTA bit,TIPOCTA char(1),INDCPICTA int,PORCEIMPUESTO decimal(18,4),IndValorRetenido bit);
                INSERT dbo.MAECONT VALUES('1435',1,'D',1,NULL,0),('2408',1,'D',1,NULL,0),('2365',1,'D',1,2.5,0),('2205',1,'D',3,NULL,0);
                INSERT dbo.PROVEEDORES VALUES('P10','N10');
                CREATE TABLE dbo.TestMode(Mode varchar(30));INSERT dbo.TestMode VALUES('OK');
                """);
            await Run("""
                CREATE PROCEDURE dbo.InsertTestDocument @XML varchar(max),@Number varchar(10)
                AS BEGIN
                    DECLARE @x xml=CONVERT(xml,@XML),@mode varchar(30)=(SELECT Mode FROM dbo.TestMode);
                    INSERT dbo.TRANSAC
                    SELECT n.value('(IDFUENTE/text())[1]','varchar(2)'),@Number,n.value('(ANOTRA/text())[1]','varchar(6)'),n.value('(FECHATRA/text())[1]','varchar(10)'),
                      n.value('(CODICTA/text())[1]','varchar(20)'),n.value('(NITTRA/text())[1]','varchar(25)'),n.value('(CLIPRV/text())[1]','varchar(10)'),
                      n.value('(INDCPITRA/text())[1]','char(1)'),n.value('(TIPOFAC/text())[1]','varchar(3)'),n.value('(NUMEFAC/text())[1]','varchar(15)'),
                      n.value('(VENCEFAC/text())[1]','varchar(10)'),CASE WHEN @mode='WRONG_REFERENCE' AND n.value('(INDCPITRA/text())[1]','char(1)')='3' THEN 'OTRA' ELSE ISNULL(n.value('(REFEFAC/text())[1]','varchar(25)'),'') END,
                      n.value('(BU/text())[1]','varchar(25)'),ISNULL(n.value('(IDCENCO/text())[1]','varchar(16)'),''),
                      ISNULL(n.value('(AUXIAUX/text())[1]','varchar(16)'),''),ISNULL(n.value('(IDITEM/text())[1]','varchar(16)'),''),
                      ISNULL(n.value('(CODPRESU/text())[1]','varchar(16)'),''),ISNULL(n.value('(NRESERVA/text())[1]','varchar(16)'),''),
                      n.value('(PORRETETRA/text())[1]','decimal(18,4)'),
                      CASE WHEN @mode='WRONG_BASIS' THEN ABS(n.value('(BASERETETRA/text())[1]','money')) ELSE n.value('(BASERETETRA/text())[1]','money') END,
                      n.value('(VALORTRA/text())[1]','money'),'AC'
                    FROM @x.nodes('/ZEUS_SQL/Documento/Transac') t(n);
                    INSERT dbo.DOCUMENT
                    SELECT h.value('(FNTEDCTO/text())[1]','varchar(2)'),@Number,h.value('(FECHDCTO/text())[1]','varchar(10)'),
                      h.value('(DESCDCTO/text())[1]','nvarchar(120)'),
                      (SELECT SUM(CASE WHEN VALORTRA>0 THEN VALORTRA ELSE 0 END) FROM dbo.TRANSAC WHERE NUMDOCTRA=@Number),
                      (SELECT -SUM(CASE WHEN VALORTRA<0 THEN VALORTRA ELSE 0 END) FROM dbo.TRANSAC WHERE NUMDOCTRA=@Number),
                      h.value('(XmlAdicionales/text())[1]','nvarchar(120)')
                    FROM @x.nodes('/ZEUS_SQL/Documento/Document') t(h);
                END
                """);
            await Run("""
                CREATE PROCEDURE dbo.spWSG_Contabilidad @Iden int,@XML varchar(max)
                AS BEGIN
                    EXEC dbo.InsertTestDocument @XML,'0100000002';
                    UPDATE f SET SACTFAC=(SELECT SUM(t.VALORTRA) FROM dbo.TRANSAC t
                      WHERE t.CODICTA=f.CODICTA AND t.CLIPRV=f.IDCLIPRV AND t.TIPOFAC=f.TIPOFACT AND t.NUMEFAC=f.NUMEFAC
                        AND t.VENCEFAC=f.VENCFAC AND t.REFEFAC=f.REFEFAC AND t.BU=f.BU)
                    FROM dbo.FACTURAS_BU f;
                    RETURN 0;
                END
                """);
            var config=settings with{ServidorEsperado=@"(localdb)\MSSQLLocalDB",BaseEsperada=database};
            var original=ZeusJournal.Build(config,source,input);
            var originalKey=Guid.NewGuid();var reversalKey=Guid.NewGuid();
            var reversal=ZeusPurchaseEntryReversalPolicy.Build(original,originalKey,config.Fuente,"0100000001",new(2026,10,1),"Corrección de la entrada equivocada");
            command.CommandText="EXEC dbo.InsertTestDocument @Xml,'0100000001'; INSERT dbo.FACTURAS_BU VALUES(@Bu,'2205','','P10','FA',@Invoice,@Due,'','202609',@Balance);";
            command.Parameters.AddWithValue("@Xml",ZeusXml.Build(original,originalKey));
            command.Parameters.AddWithValue("@Bu",config.UnidadNegocio);command.Parameters.AddWithValue("@Invoice",source.Factura);
            command.Parameters.AddWithValue("@Due",source.Vencimiento.ToString("yyyy/MM/dd",CultureInfo.InvariantCulture));
            command.Parameters.AddWithValue("@Balance",-source.Total);await command.ExecuteNonQueryAsync();command.Parameters.Clear();
            var configuration=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{
                ["Zeus:Companies:1:ConnectionString"]=cs
            }).Build();
            var transport=new ZeusTransport(configuration);
            await transport.CheckPurchaseEntryReversalAsync(1,reversal,default);
            check(true,"Preflight de reversión confirma el comprobante y la obligación exacta en Zeus");
            await Run("UPDATE dbo.FACTURAS_BU SET SACTFAC=SACTFAC+1");
            try{await transport.CheckPurchaseEntryReversalAsync(1,reversal,default);throw new Exception("Aceptó pago externo.");}
            catch(ArgumentException){check(true,"Un pago externo en Zeus bloquea la solicitud de reversión");}
            await Run("UPDATE dbo.FACTURAS_BU SET SACTFAC=SACTFAC-1");
            await transport.CheckPurchaseEntryReversalAsync(1,reversal,default);
            await Run("""
                INSERT dbo.TRANSAC SELECT IDFUENTE,'9900000001',ANOTRA,FECHATRA,CODICTA,NITTRA,CLIPRV,INDCPITRA,TIPOFAC,NUMEFAC,
                    VENCEFAC,REFEFAC,BU,IDCENCO,AUXIAUX,IDITEM,CODPRESU,NRESERVA,0,0,1,'AC'
                FROM dbo.TRANSAC WHERE INDCPITRA='3';
                """);
            var paid=await transport.SendAsync(1,reversal,reversalKey,default);
            check(paid.Estado=="RECHAZADO"&&await Count()==1,"Worker vuelve a validar un pago registrado después de solicitar la reversión");
            await Run("DELETE dbo.TRANSAC WHERE NUMDOCTRA='9900000001';UPDATE dbo.TestMode SET Mode='WRONG_REFERENCE'");
            var wrongReference=await transport.SendAsync(1,reversal,reversalKey,default);
            check(wrongReference.Estado=="RECHAZADO"&&await Count()==1,"Contrasiento con referencia de factura alterada se revierte en Zeus");
            await Run("UPDATE dbo.TestMode SET Mode='WRONG_BASIS'");
            var wrongBasis=await transport.SendAsync(1,reversal,reversalKey,default);
            check(wrongBasis.Estado=="RECHAZADO"&&await Count()==1,"Zeus debe conservar la firma inversa de las bases tributarias");
            await Run("UPDATE dbo.TestMode SET Mode='OK';UPDATE dbo.MAECONT SET PORCEIMPUESTO=3 WHERE CODICTA='2365'");
            var sent=await transport.SendAsync(1,reversal,reversalKey,default);
            check(sent.Estado=="CONTABILIZADO"&&await Count()==2,"Reversión usa tarifa histórica aunque el maestro cambió y confirma el contrasiento");
            var reconciled=await transport.ReconcileAsync(1,reversal,reversalKey,default);
            var repeated=await transport.SendAsync(1,reversal,reversalKey,default);
            check(reconciled.Estado=="CONTABILIZADO"&&repeated.Estado=="CONTABILIZADO"
                &&repeated.Documento==sent.Documento&&await Count()==2,"Respuesta perdida y reenvío conservan GUID y comprobante sin duplicar");
        }
        finally
        {
            SqlConnection.ClearAllPools();setup.CommandText=$"ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;DROP DATABASE [{database}]";
            await setup.ExecuteNonQueryAsync();
        }
    }
}
