using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.MasterData;
using NexoERP.Api.Zeus;

static class SupplierSendTests
{
    public static async Task Run(string cs,Action<bool,string> check)
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();await using var q=c.CreateCommand();
        q.CommandText="""
            CREATE TABLE dbo.TERCEROS(IDTERCERO varchar(25) PRIMARY KEY,NOMBRETER varchar(250),Deshabilitado int);
            CREATE TABLE dbo.PROVEEDORES(IDPROVE varchar(10) PRIMARY KEY,IDTERCERO varchar(25),RAZONCIAL varchar(250),Deshabilitado int);
            CREATE TABLE dbo.DIVPOLITICA(IDDIVPOLITICA varchar(25),TIPODIVPOLITICA char(1)); INSERT dbo.DIVPOLITICA VALUES('5708001','D');
            CREATE TABLE dbo.MAEZONAS(IDZONA varchar(3));INSERT dbo.MAEZONAS VALUES('01');
            CREATE TABLE dbo.SEGMENTO(IDSEGMENTO varchar(16),TIPOSEGMENTO char(1));INSERT dbo.SEGMENTO VALUES('01','D');
            CREATE TABLE dbo.TipoIdentificacion(Codigo varchar(10));INSERT dbo.TipoIdentificacion VALUES('31'),('13');
            CREATE TABLE dbo.TiposDeEmpresa(TipoEmpresa varchar(5));INSERT dbo.TiposDeEmpresa VALUES('01');
            CREATE TABLE dbo.SupplierTestMode(Mode varchar(20));INSERT dbo.SupplierTestMode VALUES('OK');
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="""
            CREATE PROCEDURE dbo.spMae_Terceros @Op varchar(50),@ManejaTransaccionalidad varchar(1),
                @IDTERCERO varchar(25),@DIRECCION varchar(250),@CIUDAD varchar(40),@TELEFONO varchar(25),@EMAIL varchar(250),
                @DIVPOLITICA varchar(25),@CODIGODANE varchar(25),@SEGMENTO varchar(16),@Usuario varchar(15),@Tipo char(1),@Deshabilitado int,
                @NOMBRETER varchar(250),@TIPOTERCE varchar(2),@TipoIdentificacion varchar(10),@DIGIVERIf varchar(5),@TIPOEMPRESA varchar(5),@Nombre1 varchar(60)=NULL,@Apellido1 varchar(60)=NULL
            AS BEGIN
                IF @Op<>'I' OR @ManejaTransaccionalidad<>'N' THROW 51000,'Contrato tercero incorrecto',1;
                INSERT dbo.TERCEROS VALUES(@IDTERCERO,@NOMBRETER,@Deshabilitado);RETURN 0;
            END
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="""
            CREATE PROCEDURE dbo.spMae_Proveedores @Op varchar(5),@ManejaTransaccionalidad varchar(1),
                @IDTERCERO varchar(25),@DIRECCION varchar(250),@CIUDAD varchar(40),@TELEFONO varchar(25),@EMAIL varchar(60),
                @DIVPOLITICA varchar(25),@CODIGODANE varchar(25),@SEGMENTO varchar(16),@Usuario varchar(15),@Tipo char(1),@Deshabilitado int,
                @IDPROVE varchar(10),@RAZONCIAL varchar(250),@IDZONA varchar(3),@CODICTA varchar(16),@WEBSITE varchar(60),@CONTACTO varchar(40),@DIPLAZO smallint,@CUPOCRE money
            AS BEGIN
                IF @Op<>'I' OR @ManejaTransaccionalidad<>'N' OR @IDPROVE<>@IDTERCERO THROW 51000,'Contrato proveedor incorrecto',1;
                IF EXISTS(SELECT 1 FROM dbo.SupplierTestMode WHERE Mode='NOINSERT') RETURN 0;
                INSERT dbo.PROVEEDORES VALUES(@IDPROVE,@IDTERCERO,@RAZONCIAL,@Deshabilitado);
                IF EXISTS(SELECT 1 FROM dbo.SupplierTestMode WHERE Mode='RETURNFAIL') RETURN 1;
                IF EXISTS(SELECT 1 FROM dbo.SupplierTestMode WHERE Mode='LATEERROR') BEGIN SELECT 'SUCCESS'; THROW 51000,'Error despues del SELECT',1; END;
                RETURN 0;
            END
            """;await q.ExecuteNonQueryAsync();
        var builder=new SqlConnectionStringBuilder(cs);
        var settings=new ZeusSettings(false,builder.DataSource,builder.InitialCatalog,"01","01","01","ERP","FA",[new("PROVEEDOR","2205")],[]);
        var transport=new ZeusTransport(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["Zeus:Companies:1:ConnectionString"]=cs}).Build());
        var supplier=new SupplierResponse(21,"NIT","802019690","1","Proveedor prueba",null,null,null,null,"Calle prueba","08001","Barranquilla",null,null,null,"CO","Colombia",null,"1234567","qa@example.invalid",null,"{\"AdditionalAccountID\":[{\"value\":\"1\"}]}",true,"5708001");
        var input=new ZeusSupplierSendRequest("01","01","01");
        check(ZeusTransport.SupplierFingerprint(settings,supplier)!=ZeusTransport.SupplierFingerprint(settings with{BaseEsperada="OtraBase"},supplier),"Huella de proveedor detecta cambio de destino");
        check(ZeusTransport.SupplierFingerprint(settings,supplier)!=ZeusTransport.SupplierFingerprint(settings,supplier with{Direccion="Otra dirección"}),"Huella de proveedor detecta cambio de datos ERP");
        check(ZeusTransport.PersonType(supplier)=="J","Persona jurídica tomada del XML");
        check(ZeusTransport.PersonType(supplier with{DatosXmlJson="{\"AdditionalAccountID\":[{\"value\":\"2\"}]}"})=="N","NIT de persona natural no se convierte en jurídica");
        check(ZeusTransport.PersonType(supplier with{DatosXmlJson=null})=="","Ausencia no inventa tipo de persona");
        check(ZeusTransport.PersonType(supplier with{TipoIdentificacion="CC"})=="","Contradicción CC jurídica requiere revisión");
        check(ZeusTransport.IdentificationCode("OTRO")=="00","Otro usa código interno de Zeus, no alterno 43");
        check((await transport.SendSupplierAsync(1,settings,supplier,input with{Zona="99"},default)).Estado=="RECHAZADO","Zona inválida bloqueada antes de crear");
        foreach(var mode in new[]{"RETURNFAIL","NOINSERT","LATEERROR"}){
            q.CommandText="UPDATE dbo.SupplierTestMode SET Mode=@M";q.Parameters.AddWithValue("@M",mode);await q.ExecuteNonQueryAsync();q.Parameters.Clear();
            check((await transport.SendSupplierAsync(1,settings,supplier,input,default)).Estado=="RECHAZADO","Rechazo de proveedor: "+mode);
            q.CommandText="SELECT (SELECT COUNT(*) FROM dbo.TERCEROS)+(SELECT COUNT(*) FROM dbo.PROVEEDORES)";
            check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"Rollback de ambos maestros: "+mode);
        }
        q.CommandText="UPDATE dbo.SupplierTestMode SET Mode='OK'";await q.ExecuteNonQueryAsync();
        var concurrent=await Task.WhenAll(transport.SendSupplierAsync(1,settings,supplier,input,default),transport.SendSupplierAsync(1,settings,supplier,input,default));
        check(concurrent.Count(x=>x.Estado=="CREADO")==1&&concurrent.Count(x=>x.Estado=="EXISTENTE")==1,"Envíos concurrentes crean un solo proveedor");
        check((await transport.SendSupplierAsync(1,settings,supplier with{RazonSocial="No sobrescribir"},new(),default)).Estado=="EXISTENTE","Repetición sin parámetros no modifica maestros");
        q.CommandText="SELECT NOMBRETER FROM dbo.TERCEROS";check((string)(await q.ExecuteScalarAsync())! == supplier.RazonSocial,"Nombre original conservado");
        q.CommandText="DELETE dbo.PROVEEDORES";await q.ExecuteNonQueryAsync();
        check((await transport.SendSupplierAsync(1,settings,supplier with{DatosXmlJson=null},input with{CategoriaFiscal=""},default)).Estado=="CREADO","Tercero existente permite crear solo proveedor");
        q.CommandText="UPDATE dbo.PROVEEDORES SET Deshabilitado=1";await q.ExecuteNonQueryAsync();
        check((await transport.SendSupplierAsync(1,settings,supplier,input,default)).Estado=="RECHAZADO","No reactiva proveedor deshabilitado");
        q.CommandText="UPDATE dbo.PROVEEDORES SET Deshabilitado=0,IDPROVE='OTRO'";await q.ExecuteNonQueryAsync();
        check((await transport.SendSupplierAsync(1,settings,supplier,input,default)).Estado=="RECHAZADO","No duplica proveedor con otro código para el mismo tercero");
        try{await transport.SendSupplierAsync(2,settings,supplier,input,default);throw new Exception("Compartió conexión");}catch(ArgumentException){check(true,"Envío de maestro no comparte conexión entre empresas");}
        try{await transport.SendSupplierAsync(1,settings,supplier with{NumeroIdentificacion="12345678901"},input,default);throw new Exception("Truncó identificación");}catch(ArgumentException){check(true,"Identificación larga se rechaza sin truncar");}
        var preview=await transport.SupplierPreviewAsync(1,settings,supplier with{NumeroIdentificacion="800000001"},default);
        check(System.Text.Json.JsonSerializer.Serialize(preview).Contains("categoriasFiscales"),"Vista previa consulta catálogos sin crear");
    }
}
