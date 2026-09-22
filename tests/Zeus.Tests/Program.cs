using System.Globalization;
using System.Text.Json;
using System.Xml.Linq;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Zeus;
using NexoERP.Api.Data;

int count=0;
void Check(bool condition,string name) { if(!condition) throw new Exception(name); Console.WriteLine("OK: "+name);count++; }
void Reject(Action action,string name) { try { action(); } catch(ArgumentException) { Check(true,name);return; } throw new Exception("No rechazó: "+name); }
var settings=new ZeusSettings(true,"server","db","01","01","01","ERP","FA",
    [new("INVENTARIO","1435"),new("PROVEEDOR","2205"),new("IVA","2408",19),new("RETEFUENTE","2365",2.5m)],
    [new(10,"P10","N10")]);
var source=new ZeusSource(20,10,"F&123",new(2026,9,21),new(2026,2,1),new(2026,3,1),116.5m,19,2.5m,[new(50,100)]);
var input=new ZeusPreviewRequest([new("IVA",19,100,19)],[new("RETEFUENTE",2.5m,100,2.5m)]);
var journal=ZeusJournal.Build(settings,source,input);
var generalRetention=settings with{Cuentas=[..settings.Cuentas.Where(a=>a.Concepto!="RETEFUENTE"),new("RETEFUENTE","236599")]};
Check(ZeusJournal.Build(generalRetention,source,input).Movimientos.Single(m=>m.Regla.Concepto=="RETEFUENTE").Regla.Cuenta=="236599","Retención usa cuenta general de empresa cuando no hay tarifa específica");
var rateRetention=generalRetention with{Cuentas=[..generalRetention.Cuentas,new("RETEFUENTE","236525",2.5m)]};
Check(ZeusJournal.Build(rateRetention,source,input).Movimientos.Single(m=>m.Regla.Concepto=="RETEFUENTE").Regla.Cuenta=="236525","Cuenta específica de tarifa prevalece sobre la general");
var otherRate=input with{Retenciones=[new("RETEFUENTE",3,100,3)]};
Check(ZeusJournal.Build(rateRetention,source with{Total=116,Retenciones=3},otherRate).Movimientos.Single(m=>m.Regla.Concepto=="RETEFUENTE").Regla.Cuenta=="236599","Otra tarifa utiliza la general sin inventar cuentas");
var linked=ZeusJournal.WithZeusRetentionRates(settings with{Cuentas=[new("RETEFUENTE","236525",99)]},[new("236525","Tarifa",2.5m,false)]);
Check(linked.Cuentas.Single().Tarifa==2.5m,"Backend toma porcentaje Zeus e ignora tarifa digitada por cliente");
ZeusJournal.ValidateRetentionAccounts(linked,[new("236525","Tarifa",2.5m,false)]);
Check(true,"Valida cuentas de retención contra plan de la empresa");
Reject(()=>ZeusJournal.ValidateRetentionAccounts(rateRetention,[new("236599","Otra empresa")]),"Rechaza cuenta de retención que no está en el plan consultado");
Reject(()=>ZeusJournal.WithZeusRetentionRates(settings with{Cuentas=[new("RETEFUENTE","2365"),new("RETEFUENTE","2366")]},[new("2365","Una",2.5m,false),new("2366","Otra",2.5m,false)]),"No permite dos cuentas para el mismo tipo y porcentaje Zeus");
foreach(var rate in new ZeusChartAccount[]{new("2365","Sin porcentaje"),new("2365","Base retenida",100,true),new("2365","Sin indicador",2.5m),new("2365","Precisión incompatible",0.123456m,false)})
    Reject(()=>ZeusJournal.WithZeusRetentionRates(settings,[rate]),"No inventa ni redondea tarifas ambiguas del maestro Zeus");
Check(ZeusJournal.WithZeusRetentionRates(settings,[new("2365","ICA",0.966m,false)]).Cuentas.Single(a=>a.Concepto=="RETEFUENTE").Tarifa==0.966m,"PORCEIMPUESTO se conserva como porcentaje sin dividir por mil");
Reject(()=>ZeusJournal.ValidateRetentionAccounts(settings with{Cuentas=[new("RETEIVA","2367",0)]},[new("2367","ReteIVA")]),"Tarifa cero no sustituye selección de todas las tarifas");
foreach(var retention in new[]{"RETEIVA","RETEICA"})
{
    var config=settings with{Cuentas=[..settings.Cuentas,new(retention,"236999")]};
    Check(ZeusJournal.Build(config,source,input with{Retenciones=[new(retention,2.5m,100,2.5m)]}).Movimientos.Single(m=>m.Regla.Concepto==retention).Regla.Cuenta=="236999","Cuenta general independiente para "+retention);
}
try{ZeusJournal.Build(settings with{Cuentas=settings.Cuentas.Where(a=>a.Concepto!="RETEFUENTE").ToArray()},source,input);throw new Exception("No indicó cuenta faltante");}
catch(ArgumentException e){Check(e.Message.Contains("RETEFUENTE")&&e.Message.Contains("2.5")&&e.Message.Contains("Retenciones"),"Cuenta faltante identifica tipo, tarifa y pantalla de configuración");}
Check(journal.Movimientos.Sum(m=>m.Valor)==0,"Cuadre exacto con retención");
Check(journal.Movimientos.Last().Valor==-116.5m,"Proveedor por valor neto");
Check(journal.Movimientos.Single(m=>m.Regla.Concepto=="RETEFUENTE").Base==-100,"Base de retención con signo de crédito");
Reject(()=>ZeusJournal.Build(settings,source,input with{Impuestos=[]}),"Rechaza impuesto omitido");
Reject(()=>ZeusJournal.Build(settings,source,input with{Retenciones=[]}),"Rechaza retención omitida");
Reject(()=>ZeusJournal.Build(settings,source with{Total=120},input),"No inventa redondeo para cuadrar");
Reject(()=>ZeusJournal.Build(settings,source,input with{Impuestos=[new("IVA",19,100,18)]}),"Verifica base por tarifa");
Reject(()=>ZeusJournal.Build(settings,source,input with{Retenciones=[new("AUTORRETENCION",2.5m,100,2.5m)]}),"No confunde autorretenciones");
Reject(()=>ZeusJournal.Build(settings with{Proveedores=[]},source,input),"Requiere homologación por empresa");
Reject(()=>ZeusJournal.Build(settings with{Cuentas=[new("PROVEEDOR","2205")]},source,input),"Bloquea cuentas faltantes");
Reject(()=>ZeusJournal.Validate(settings with{Serie="A1"}),"Serie numérica estricta");
Reject(()=>ZeusJournal.Validate(settings with{Cuentas=[..settings.Cuentas,settings.Cuentas[0]]}),"Rechaza reglas ambiguas");
Reject(()=>ZeusJournal.Build(settings,source with{Lineas=[new(50,100.001m)]},input),"No trunca importes");
var specific=settings with{Cuentas=[..settings.Cuentas,new("INVENTARIO","143501",ArticuloId:50),new("PROVEEDOR","220510",ProveedorId:10)]};
var resolved=ZeusJournal.Build(specific,source,input);
Check(resolved.Movimientos[0].Regla.Cuenta=="143501","Prioridad de artículo");
Check(resolved.Movimientos.Last().Regla.Cuenta=="220510","Prioridad de proveedor");
var co446643=source with{Factura="CO446643",Total=815501.05m,Impuestos=130206.05m,Retenciones=0,Lineas=[new(122,327426m,1,"143501001","240810008"),new(123,357869m,1,"143501001","240810008")]};
var coJournal=ZeusJournal.Build(settings,co446643,new([new("IVA",19,685295m,130206.05m)],[]));
Check(coJournal.Movimientos.Where(m=>m.Valor>0).Sum(m=>m.Valor)==815501.05m&&coJournal.Movimientos.Sum(m=>m.Valor)==0,"CO446643 cuadra inventario e IVA sin duplicar cargos");
var other=settings with{Cuentas=[..settings.Cuentas.Where(a=>a.Concepto!="IVA"),new("IVA","240899",19)]};
// Valores de Suzuki: conservar los importes del XML, no recalcular el IVA registrado.
var suzukiBases=new[]{8034706m,8034706m,8034706m,8034706m,8034706m,401735m};
var suzukiAmounts=new[]{1526594m,1526594m,1526594m,1526594m,1526594m,76330m};
var suzukiXml=new XElement("Invoice",suzukiBases.Select((basis,i)=>new XElement("InvoiceLine",
    new XElement("ID",i+1),new XElement("TaxTotal",new XElement("TaxSubtotal",new XElement("TaxableAmount",basis),new XElement("TaxAmount",suzukiAmounts[i]),
        new XElement("TaxCategory",new XElement("Percent",19),new XElement("TaxScheme",new XElement("ID","01")))))))).ToString();
var suzukiInput=ZeusXmlTaxes.Parse(suzukiXml,Enumerable.Range(1,6).ToDictionary(i=>i.ToString(),i=>(long?)1),0);
var suzuki=source with{Factura="191109627",Total=48284565m,Impuestos=7709300m,Retenciones=0,
    Lineas=suzukiBases.Select(b=>new ZeusSourceLine(50,b,1,"1435","2408")).ToArray()};
var suzukiJournal=ZeusJournal.Build(settings,suzuki,suzukiInput);
Check(suzukiJournal.Movimientos.Where(m=>m.Regla.Concepto=="IVA").Select(m=>m.Valor).SequenceEqual(suzukiAmounts),"Suzuki conserva el IVA XML redondeado hacia abajo y arriba por línea");
Check(suzukiJournal.Movimientos.Sum(m=>m.Valor)==0&&suzukiJournal.Movimientos.Last().Valor==-48284565m,"Suzuki cuadra exactamente 48.284.565 sin ajustes ni cambio de cartera");
Check(!suzukiJournal.Movimientos.Any(m=>m.Regla.Concepto=="REDONDEO"),"Redondeo declarado no crea movimientos adicionales");
Reject(()=>ZeusJournal.Build(settings,suzuki with{Total=suzuki.Total+1},suzukiInput),"IVA al peso no relaja el cuadre del total de factura");
Reject(()=>ZeusJournal.Build(settings,suzuki with{Impuestos=suzuki.Impuestos+1},suzukiInput),"IVA al peso no relaja la suma del impuesto guardado");
void CheckVatRounding(decimal basis,decimal amount,bool accepted,string label)
{
    var testSource=source with{Total=basis+amount,Impuestos=amount,Retenciones=0,Lineas=[new(50,basis)]};
    var testInput=new ZeusPreviewRequest([new("IVA",19,basis,amount)],[]);
    if(accepted)Check(ZeusJournal.Build(settings,testSource,testInput).Movimientos.Sum(m=>m.Valor)==0,label);
    else Reject(()=>ZeusJournal.Build(settings,testSource,testInput),label);
}
CheckVatRounding(50,10,true,"IVA 9,50 admite redondeo al peso 10");
CheckVatRounding(50,9,false,"IVA 9,50 rechaza el entero incorrecto 9");
CheckVatRounding(10,2,true,"IVA 1,90 admite 2 pesos");
CheckVatRounding(10,1.8m,false,"No admite diferencias decimales arbitrarias menores de un peso");
CheckVatRounding(100,18,false,"No admite un peso de diferencia cuando el IVA es exacto");
CheckVatRounding(100,19.01m,true,"Conserva tolerancia previa de un centavo");
Reject(()=>ZeusJournal.Build(settings,source with{Total=116,Retenciones=3},input with{Retenciones=[new("RETEFUENTE",2.5m,100,3)]}),"No extiende redondeo al peso a las retenciones");
Check(ZeusJournal.Build(other,source,input).Movimientos[1].Regla.Cuenta=="240899","Configuración de otra empresa independiente");
var key=Guid.NewGuid();var xml=ZeusXml.Build(journal,key);var root=XElement.Parse(xml);
var doc=root.Element("Documento")!;var header=doc.Element("Document")!;var lines=doc.Elements("Transac").ToArray();
Check(root.Name=="ZEUS_SQL" && lines.Length==4,"Contrato XML y número de movimientos");
Check(header.Element("NUMEDCTO")!.Value=="01NUEVO","Solicitud de consecutivo Zeus");
Check(header.Element("DESCDCTO")!.Value==ZeusXml.Marker(key),"Clave estable en comprobante");
Check(lines[0].Element("NUMEFAC")!.Value=="F&123","Escape XML de factura");
Check(lines[0].Element("FECHATRA")!.Value=="2026/09/21" && lines[0].Element("Fechafact")!.Value=="2026/02/01","Fecha contable distinta de factura");
Check(doc.Element("Lineas") is null,"No activa escenarios fiscales de ventas");
var original=CultureInfo.CurrentCulture;
try { CultureInfo.CurrentCulture=new("es-CO");Check(ZeusXml.Build(journal,key)==xml,"Decimales independientes de cultura"); } finally { CultureInfo.CurrentCulture=original; }
var unicode=journal with{Origen=source with{Factura="Ñ-123"}};
Check(ZeusXml.Build(unicode,key).All(c=>c<=127) && XElement.Parse(ZeusXml.Build(unicode,key)).Descendants("NUMEFAC").First().Value=="Ñ-123","Unicode conservado en varchar XML");
Check(ZeusRepository.Fingerprint(journal)==ZeusRepository.Fingerprint(journal),"Huella estable");
Check(ZeusRepository.Fingerprint(journal)!=ZeusRepository.Fingerprint(resolved),"Huella detecta cambio de cuentas");
Check(ZeusRepository.Fingerprint(journal)==ZeusRepository.Fingerprint(journal with{Origen=source with{Total=116.5000m}}),"Huella ignora ceros decimales sin cambio de valor");
AutomaticPostingTests.Unit(Check);
if(args.Contains("--sql"))
{
    // Únicamente una base desechable propia en LocalDB; jamás usa .env ni Zeus remoto.
    var db="NexoZeusTests_"+Guid.NewGuid().ToString("N");
    await using var admin=new SqlConnection("Server=(localdb)\\MSSQLLocalDB;Database=master;Integrated Security=True;TrustServerCertificate=True");
    await admin.OpenAsync();await using var setup=admin.CreateCommand();setup.CommandText=$"CREATE DATABASE [{db}]";await setup.ExecuteNonQueryAsync();
    setup.CommandText=$"ALTER DATABASE [{db}] SET READ_COMMITTED_SNAPSHOT ON";await setup.ExecuteNonQueryAsync();
    var cs=$"Server=(localdb)\\MSSQLLocalDB;Database={db};Integrated Security=True;TrustServerCertificate=True";
    try
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();await using var q=c.CreateCommand();
        q.CommandText="""
            CREATE TABLE dbo.DOCUMENT(FNTEDCTO varchar(2),NUMEDCTO varchar(10),FECHDCTO varchar(10),DESCDCTO varchar(120),SUDBDCTO money,SUCRDCTO money);
            CREATE TABLE dbo.TRANSAC(IDFUENTE varchar(2),NUMDOCTRA varchar(10),CODICTA varchar(20),VALORTRA money,STATUSTRA varchar(2),BU varchar(20));
            CREATE TABLE dbo.TestMode(Mode varchar(20));INSERT dbo.TestMode VALUES('OK');
            CREATE TABLE dbo.MAECONT(CODICTA varchar(20),HABILITARCTA bit,TIPOCTA char(1),INDCPICTA int);
            INSERT dbo.MAECONT VALUES('1435',1,'D',1),('2408',1,'D',1),('2365',1,'D',1),('2205',1,'D',3);
            ALTER TABLE dbo.MAECONT ADD PORCEIMPUESTO decimal(18,6),IndValorRetenido bit;
            EXEC('UPDATE dbo.MAECONT SET PORCEIMPUESTO=2.5,IndValorRetenido=0 WHERE CODICTA=''2365''');
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="""
            CREATE PROCEDURE dbo.TestAccountingValidation AS BEGIN RAISERROR('Validación contable de prueba: centro de costo obligatorio.',16,1); END
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="""
            CREATE PROCEDURE dbo.spWSG_Contabilidad @Iden int,@XML varchar(max) AS
            BEGIN
              SET NOCOUNT ON;
              IF @Iden<>16 THROW 51990,'Iden incorrecto',1;
              IF EXISTS(SELECT 1 FROM dbo.TestMode WHERE Mode='NOINSERT') RETURN 0;
              IF EXISTS(SELECT 1 FROM dbo.TestMode WHERE Mode='RETURNFAIL') RETURN 3;
              DECLARE @X xml=CONVERT(xml,@XML);
              INSERT dbo.DOCUMENT
              SELECT x.value('(FNTEDCTO/text())[1]','varchar(2)'),'0100000001',x.value('(FECHDCTO/text())[1]','varchar(10)'),x.value('(DESCDCTO/text())[1]','varchar(120)'),119,119
              FROM @X.nodes('/ZEUS_SQL/Documento/Document') d(x);
              INSERT dbo.TRANSAC SELECT x.value('(IDFUENTE/text())[1]','varchar(2)'),'0100000001',x.value('(CODICTA/text())[1]','varchar(20)'),x.value('(VALORTRA/text())[1]','money'),'XA',x.value('(BU/text())[1]','varchar(20)')
              FROM @X.nodes('/ZEUS_SQL/Documento/Transac') d(x);
              IF EXISTS(SELECT 1 FROM dbo.TestMode WHERE Mode='WRONGTOTAL') UPDATE dbo.DOCUMENT SET SUDBDCTO=120;
              IF EXISTS(SELECT 1 FROM dbo.TestMode WHERE Mode='WRONGACCOUNT') UPDATE dbo.TRANSAC SET CODICTA='999';
              SELECT '01' Fuente,'0100000001' Documento;
              IF EXISTS(SELECT 1 FROM dbo.TestMode WHERE Mode='LATEERROR') THROW 51991,'Fallo despues del SELECT',1;
              IF EXISTS(SELECT 1 FROM dbo.TestMode WHERE Mode='RULE50000') EXEC dbo.TestAccountingValidation;
              IF EXISTS(SELECT 1 FROM dbo.TestMode WHERE Mode='SECRET') RAISERROR('Error de prueba; pwd="secreto privado"; revisar configuración',16,1);
              RETURN 0;
            END
            """;await q.ExecuteNonQueryAsync();
        var conf=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["Zeus:Companies:1:ConnectionString"]=cs}).Build();
        var transport=new ZeusTransport(conf);
        var testJournal=journal with{Configuracion=settings with{ServidorEsperado="(localdb)\\MSSQLLocalDB",BaseEsperada=db}};
        setup.CommandText=$"ALTER DATABASE [{db}] SET COMPATIBILITY_LEVEL=100";await setup.ExecuteNonQueryAsync();
        q.CommandText="SELECT * FROM OPENJSON(N'[]') WITH(Cuenta varchar(20),Proveedor bit)";
        try{await q.ExecuteNonQueryAsync();throw new Exception("No reprodujo incompatibilidad");}
        catch(SqlException e)when(e.Number is 319 or 208){Check(true,"Reproduce fallo de consulta anterior con compatibilidad Zeus 100");}
        var sent=await transport.SendAsync(1,testJournal,key,default);
        Check(sent.Estado=="CONTABILIZADO" && sent.Documento=="0100000001","Compatibilidad 100: transporte confirma después de verificar y commit");
        q.CommandText="UPDATE dbo.MAECONT SET PORCEIMPUESTO=3 WHERE CODICTA='2365'";await q.ExecuteNonQueryAsync();
        var staleRate=await transport.SendAsync(1,testJournal,Guid.NewGuid(),default);
        Check(staleRate.Estado=="RECHAZADO"&&staleRate.Error!.Contains("PORCEIMPUESTO"),"Revalida tarifa viva en Zeus antes de contabilizar y bloquea cambios posteriores");
        q.CommandText="UPDATE dbo.MAECONT SET PORCEIMPUESTO=2.5 WHERE CODICTA='2365'";await q.ExecuteNonQueryAsync();
        var repeated=await transport.SendAsync(1,testJournal,key,default);
        q.CommandText="SELECT COUNT(*) FROM dbo.DOCUMENT";
        Check(repeated.Estado=="CONTABILIZADO" && Convert.ToInt32(await q.ExecuteScalarAsync())==1,"Reenvío con misma clave no duplica");
        Check((await transport.ReconcileAsync(1,testJournal,key,default)).Estado=="CONTABILIZADO","Conciliación de éxito incierto");
        Check((await transport.ReconcileAsync(1,testJournal,Guid.NewGuid(),default)).Estado=="INCIERTO","Ausencia no autoriza reenvío");
        Check((await transport.SendAsync(2,testJournal,Guid.NewGuid(),default)).Estado=="RECHAZADO","No comparte conexión con otra empresa");
        Check((await transport.SendAsync(1,testJournal with{Configuracion=testJournal.Configuracion with{BaseEsperada="otra"}},Guid.NewGuid(),default)).Estado=="RECHAZADO","Bloquea destino diferente");
        foreach(var mode in new[]{"NOINSERT","RETURNFAIL","WRONGTOTAL","WRONGACCOUNT","LATEERROR","RULE50000","SECRET"})
        {
            q.CommandText="DELETE dbo.TRANSAC;DELETE dbo.DOCUMENT;UPDATE dbo.TestMode SET Mode=@Mode";q.Parameters.Clear();q.Parameters.AddWithValue("@Mode",mode);await q.ExecuteNonQueryAsync();
            var failed=await transport.SendAsync(1,testJournal,Guid.NewGuid(),default);
            q.CommandText="SELECT COUNT(*) FROM dbo.DOCUMENT";
            Check(failed.Estado!="CONTABILIZADO" && Convert.ToInt32(await q.ExecuteScalarAsync())==0,"Rollback y sin falso éxito: "+mode);
            if(mode=="RULE50000")Check(failed.Error!.Contains("SQL 50000")&&failed.Error.Contains("TestAccountingValidation")&&failed.Error.Contains("línea")&&failed.Error.Contains("centro de costo obligatorio")&&failed.Error.Contains("Etapa: dbo.spWSG_Contabilidad"),"Conserva mensaje real 50000, procedimiento anidado, línea y etapa después del SELECT");
            if(mode=="LATEERROR")Check(failed.Error!.Contains("Fallo despues del SELECT"),"No pierde la causa SQL tardía al revertir");
            if(mode=="RETURNFAIL")Check(failed.Error!.Contains("retorno 3"),"Informa el código de retorno del procedimiento contable");
            if(mode=="SECRET")Check(!failed.Error!.Contains("secreto privado")&&failed.Error.Contains("[oculto]"),"Diagnóstico contable oculta contraseñas antes de persistir");
        }
        q.Parameters.Clear();
        q.CommandText="UPDATE dbo.TestMode SET Mode='OK'";await q.ExecuteNonQueryAsync();
        foreach(var account in new[]{"999","2205","1435&<"})
        {
            var invalid=testJournal with{Movimientos=testJournal.Movimientos.Select((m,i)=>i==0?m with{Regla=m.Regla with{Cuenta=account}}:m).ToArray()};
            var rejected=await transport.SendAsync(1,invalid,Guid.NewGuid(),default);
            Check(rejected.Estado=="RECHAZADO"&&rejected.Error!.Contains("51711"),"Compatibilidad 100: rechaza cuenta inexistente, incompatible o especial sin perder validación: "+account);
        }
        q.CommandText="SELECT COUNT(*) FROM dbo.DOCUMENT";Check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"Cuentas rechazadas no dejan comprobantes en compatibilidad 100");
        setup.CommandText=$"ALTER DATABASE [{db}] SET COMPATIBILITY_LEVEL=150";await setup.ExecuteNonQueryAsync();
        q.CommandText="""
            EXEC('CREATE SCHEMA core');EXEC('CREATE SCHEMA inv');EXEC('CREATE SCHEMA seg');EXEC('CREATE SCHEMA comp');EXEC('CREATE SCHEMA audit');
            CREATE TABLE core.SchemaMigration(MigrationId varchar(50) PRIMARY KEY,Descripcion nvarchar(250));
            CREATE TABLE core.Empresa(EmpresaId bigint PRIMARY KEY);INSERT core.Empresa VALUES(1),(2);
            CREATE TABLE seg.Usuario(UsuarioId bigint PRIMARY KEY);INSERT seg.Usuario VALUES(1);
            EXEC('CREATE SCHEMA ter');
            CREATE TABLE ter.Tercero(EmpresaId bigint,TerceroId bigint,RazonSocial nvarchar(200));
            INSERT ter.Tercero VALUES(1,10,N'Proveedor de prueba');
            CREATE TABLE core.Probe(EmpresaId bigint);
            CREATE TABLE inv.RecepcionMercancia(RecepcionMercanciaId bigint PRIMARY KEY,EmpresaId bigint,Estado varchar(15),TerceroId bigint,DocumentoProveedorId bigint,FechaContable date,UNIQUE(EmpresaId,RecepcionMercanciaId));
            CREATE TABLE comp.DocumentoProveedor(DocumentoProveedorId bigint,EmpresaId bigint,NumeroDocumento varchar(50),FechaDocumento date,FechaVencimiento date,TotalPagar decimal(20,4),ImpuestoTotal decimal(20,4),Moneda char(3),CargoTotal decimal(20,4),Estado varchar(15));
            CREATE TABLE comp.DocumentoProveedorLinea(DocumentoProveedorLineaId bigint,EmpresaId bigint,DocumentoProveedorId bigint,NumeroLinea int,ArticuloId bigint,TotalNeto decimal(20,4),Retencion decimal(20,4),Clasificacion varchar(25),Cargo decimal(20,4));
            CREATE TABLE inv.RecepcionMercanciaLinea(EmpresaId bigint,RecepcionMercanciaId bigint,DocumentoProveedorLineaId bigint);
            CREATE TABLE audit.Evento(EmpresaId bigint,UsuarioId bigint NULL,Operacion varchar(50),Entidad varchar(100),EntidadId nvarchar(100),ValoresPosteriores nvarchar(max),AplicacionOrigen varchar(50));
            INSERT inv.RecepcionMercancia VALUES(20,1,'VALIDADA',10,100,'20260921');
            INSERT comp.DocumentoProveedor VALUES(100,1,'F&123','20260201','20260301',116.5,19,'COP',0,'CONTABILIZADO');
            INSERT comp.DocumentoProveedorLinea VALUES(1000,1,100,1,50,100,2.5,'INVENTARIO',0);
            INSERT inv.RecepcionMercanciaLinea VALUES(1,20,1000);
            ALTER TABLE ter.Tercero ADD NumeroIdentificacion nvarchar(30) NOT NULL DEFAULT '901528333';
            ALTER TABLE comp.DocumentoProveedorLinea ADD SubtotalBruto decimal(20,4) NOT NULL DEFAULT 100,Descuento decimal(20,4) NOT NULL DEFAULT 0;
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="""
            CREATE FUNCTION seg.fn_EmpresaAccess(@EmpresaId bigint) RETURNS TABLE WITH SCHEMABINDING AS
            RETURN SELECT 1 permitido WHERE @EmpresaId=TRY_CONVERT(bigint,SESSION_CONTEXT(N'EmpresaId')) OR TRY_CONVERT(bit,SESSION_CONTEXT(N'BypassRls'))=1;
            """;await q.ExecuteNonQueryAsync();
        q.CommandText="CREATE SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.Probe WITH(STATE=ON)";
        await q.ExecuteNonQueryAsync();
        var dir=new DirectoryInfo(AppContext.BaseDirectory);
        while(dir is not null && !Directory.Exists(Path.Combine(dir.FullName,"database","migrations"))) dir=dir.Parent;
        var migration=await File.ReadAllTextAsync(Path.Combine(dir!.FullName,"database","migrations","049_zeus_integration.sql"));
        for(var pass=0;pass<2;pass++)
        {
            foreach(var batch in System.Text.RegularExpressions.Regex.Split(migration,@"(?im)^\s*GO\s*$"))
            {
                if(string.IsNullOrWhiteSpace(batch)) continue;
                q.CommandText=batch;await q.ExecuteNonQueryAsync();
            }
        }
        Check(true,"Migración 049 ejecutable e idempotente en base aislada");
        q.CommandText="CREATE TABLE inv.Bodega(EmpresaId bigint,BodegaId bigint,Activa bit,PRIMARY KEY(EmpresaId,BodegaId));INSERT inv.Bodega VALUES(1,1,1),(1,2,1),(2,3,1);ALTER TABLE inv.RecepcionMercancia ADD BodegaId bigint;ALTER TABLE inv.RecepcionMercanciaLinea ADD BodegaId bigint;EXEC('UPDATE inv.RecepcionMercancia SET BodegaId=1');";await q.ExecuteNonQueryAsync();
        var warehouseMigration=await File.ReadAllTextAsync(Path.Combine(dir!.FullName,"database","migrations","052_warehouse_zeus_accounts.sql"));
        for(var pass=0;pass<2;pass++)foreach(var batch in System.Text.RegularExpressions.Regex.Split(warehouseMigration,@"(?im)^\s*GO\s*$"))
        {if(string.IsNullOrWhiteSpace(batch))continue;q.CommandText=batch;await q.ExecuteNonQueryAsync();}
        Check(true,"Migración 052 ejecutable e idempotente en base aislada");
        q.CommandText="ALTER TABLE ter.Tercero ADD PaisCodigo nvarchar(10),CiudadCodigo nvarchar(20)";await q.ExecuteNonQueryAsync();
        var divisionMigration=await File.ReadAllTextAsync(Path.Combine(dir!.FullName,"database","migrations","051_supplier_zeus_political_division.sql"));
        for(var pass=0;pass<2;pass++)foreach(var batch in System.Text.RegularExpressions.Regex.Split(divisionMigration,@"(?im)^\s*GO\s*$"))
        {if(string.IsNullOrWhiteSpace(batch))continue;q.CommandText=batch;await q.ExecuteNonQueryAsync();}
        foreach(var example in new[]{("CO","05001","5705001"),("CO","11001","5711001"),("57","05001","5705001"),("US","11001",""),("CO","5001",""),("CO","05A01","")})
        {
            q.CommandText="UPDATE ter.Tercero SET PaisCodigo=@Country,CiudadCodigo=@City;SELECT DivisionPoliticaZeus FROM ter.Tercero";
            q.Parameters.AddWithValue("@Country",example.Item1);q.Parameters.AddWithValue("@City",example.Item2);
            Check(Convert.ToString(await q.ExecuteScalarAsync())==example.Item3,"División SQL calculada: "+example.Item1+" / "+example.Item2);q.Parameters.Clear();
        }
        q.CommandText="UPDATE ter.Tercero SET PaisCodigo=NULL,CiudadCodigo=NULL";await q.ExecuteNonQueryAsync();
        var erpConf=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["ConnectionStrings:NexoErp"]=cs}).Build();
        var repository=new ZeusRepository(new TenantConnectionFactory(erpConf));
        await repository.SaveSettingsAsync(1,1,new(0,settings),default);
        Check((await repository.SettingsAsync(1,default))?.Version==1,"Configuración persistida con versión");
        Check(await repository.SettingsAsync(2,default) is null,"Lectura no cruza empresas");
        try { await repository.SaveSettingsAsync(1,1,new(0,settings),default);throw new Exception("Versión obsoleta aceptada"); }
        catch(SqlException e) when(e.Number==51702) {Check(true,"Bloquea versión obsoleta");}
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1; BEGIN TRANSACTION; UPDATE inv.RecepcionMercancia SET Estado='CONTABILIZADA' WHERE RecepcionMercanciaId=20; SELECT COUNT(*) FROM core.ZeusEnvio;";
        Check(Convert.ToInt32(await q.ExecuteScalarAsync())==1,"Trigger encola en transacción de entrada");
        q.CommandText="ROLLBACK;SELECT COUNT(*) FROM core.ZeusEnvio";
        Check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"Rollback de entrada elimina tarea pendiente");
        q.CommandText="UPDATE inv.RecepcionMercancia SET Estado='CONTABILIZADA' WHERE RecepcionMercanciaId=20";await q.ExecuteNonQueryAsync();
        var preview=await repository.PreviewAsync(1,20,input,default);
        Check(preview is not null,"Vista previa usa consultas reales del repositorio");
        q.CommandText="UPDATE core.ZeusConfiguracion SET Configuracion=JSON_MODIFY(Configuracion,'$.Proveedores',JSON_QUERY('[]')) WHERE EmpresaId=1;UPDATE comp.DocumentoProveedorLinea SET Cargo=5,SubtotalBruto=110,Descuento=15";await q.ExecuteNonQueryAsync();
        var automatic=System.Text.Json.JsonSerializer.SerializeToElement(await repository.PreviewAsync(1,20,input,default)).GetProperty("comprobante").Deserialize<ZeusSnapshot>()!;
        Check(automatic.Proveedor==new ZeusSupplier(10,"901528333","901528333"),"Sin homologación manual usa la identificación ERP como proveedor y tercero");
        Check(automatic.Movimientos[0].Valor==100&&automatic.Movimientos.Sum(m=>m.Valor)==0,"Cargo incluido en neto no se suma dos veces");
        Check(await repository.EligibleAsync(1,automatic,default),"Worker reconstruye identidad automática y cargos incluidos");
        q.CommandText="UPDATE comp.DocumentoProveedorLinea SET Cargo=6";await q.ExecuteNonQueryAsync();
        try{await repository.PreviewAsync(1,20,input,default);throw new Exception("Aceptó cargo sin cuadrar");}catch(ArgumentException){Check(true,"Rechaza neto inconsistente con cargo");}
        q.CommandText="UPDATE comp.DocumentoProveedorLinea SET Cargo=0,SubtotalBruto=100,Descuento=0;UPDATE ter.Tercero SET NumeroIdentificacion='901-528333'";await q.ExecuteNonQueryAsync();
        try{await repository.PreviewAsync(1,20,input,default);throw new Exception("Aceptó NIT inválido");}catch(ArgumentException){Check(true,"No altera ni recorta identificación inválida");}
        q.CommandText="UPDATE ter.Tercero SET NumeroIdentificacion='901528333';UPDATE core.ZeusConfiguracion SET Configuracion=@Restore WHERE EmpresaId=1";q.Parameters.AddWithValue("@Restore",System.Text.Json.JsonSerializer.Serialize(settings));await q.ExecuteNonQueryAsync();q.Parameters.Clear();
        q.CommandText="UPDATE ter.Tercero SET PaisCodigo='CO',CiudadCodigo='05001'";await q.ExecuteNonQueryAsync();
        var divisionPreview=System.Text.Json.JsonSerializer.Serialize(await repository.PreviewAsync(1,20,input,default));
        Check(divisionPreview.Contains("\"DivisionPoliticaZeus\":\"5705001\""),"Vista previa Zeus lleva división del proveedor de la empresa");
        q.CommandText="UPDATE ter.Tercero SET PaisCodigo=NULL,CiudadCodigo=NULL";await q.ExecuteNonQueryAsync();
        var approve=new ZeusApproveRequest(input.Impuestos,input.Retenciones,ZeusRepository.Fingerprint(journal));
        var jobId=await repository.ApproveAsync(1,20,1,approve,default);
        var jobs=(List<Dictionary<string,object?>>)await repository.ListAsync(1,"",0,default);
        Check(jobs.Count==1 && (string)jobs[0]["Factura"]! == "F&123","Listado sin filtro incluye factura y proveedor");
        Check(((List<Dictionary<string,object?>>)await repository.ListAsync(2,null,0,default)).Count==0,"Listado no cruza empresas");
        var receipts=(List<Dictionary<string,object?>>)await repository.ReceiptsAsync(1,"Proveedor",default);
        Check(receipts.Count==1 && (decimal)receipts[0]["Retenciones"]! == 2.5m,"Buscador obtiene retenciones persistidas");
        Check(((List<Dictionary<string,object?>>)await repository.ReceiptsAsync(2,"",default)).Count==0,"Buscador no cruza empresas");
        Check(jobId==await repository.ApproveAsync(1,20,1,approve,default),"Aprobación repetida devuelve mismo envío");
        try { await repository.ApproveAsync(2,20,1,approve,default);throw new Exception("Aprobó otra empresa"); }
        catch(ArgumentException) { Check(true,"No aprueba entrada de otra empresa"); }
        try { await repository.ApproveAsync(1,20,1,approve with{Huella="obsoleta"},default);throw new Exception("Aprobó huella obsoleta"); }
        catch(ArgumentException) { Check(true,"Rechaza vista previa obsoleta"); }
        try { await repository.SaveSettingsAsync(1,1,new(1,settings),default);throw new Exception("Cambió destino pendiente"); }
        catch(SqlException e) when(e.Number==51701) { Check(true,"Destino bloqueado mientras hay envío pendiente"); }
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=2;SELECT COUNT(*) FROM core.ZeusEnvio";
        Check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"RLS oculta envíos de otra empresa incluso sin WHERE");
        q.CommandText="UPDATE core.ZeusEnvio SET Estado='INCIERTO' WHERE ZeusEnvioId="+jobId+";SELECT @@ROWCOUNT";
        Check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"RLS impide modificar envío ajeno");
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;UPDATE core.ZeusEnvio SET Estado='INCIERTO' WHERE ZeusEnvioId="+jobId;await q.ExecuteNonQueryAsync();
        try { await repository.ApproveAsync(1,20,1,approve,default);throw new Exception("Reenvió resultado incierto"); }
        catch(SqlException e) when(e.Number==51704) {Check(true,"Resultado incierto bloquea reenvío");}
        var fromPreview=System.Text.Json.JsonSerializer.Deserialize<ZeusSnapshot>(System.Text.Json.JsonSerializer.SerializeToElement(preview).GetProperty("comprobante"))!;
        Check(await repository.EligibleAsync(1,fromPreview,default),"Worker comprueba snapshot contra datos actuales");
        q.CommandText="UPDATE comp.DocumentoProveedor SET TotalPagar=120";await q.ExecuteNonQueryAsync();
        Check(!await repository.EligibleAsync(1,fromPreview,default),"Worker bloquea importes modificados después de aprobar");
        q.CommandText="UPDATE comp.DocumentoProveedor SET TotalPagar=116.5;UPDATE core.ZeusEnvio SET Estado='PENDIENTE' WHERE ZeusEnvioId="+jobId;await q.ExecuteNonQueryAsync();
        var claims=await Task.WhenAll(repository.ClaimAsync(default),repository.ClaimAsync(default));
        Check(claims.Count(x=>x is not null)==1,"Dos workers no toman el mismo envío");
        try {q.CommandText="UPDATE inv.RecepcionMercancia SET Estado='REVERTIDA' WHERE RecepcionMercanciaId=20";await q.ExecuteNonQueryAsync();throw new Exception("Revirtió durante envío");}
        catch(SqlException e) when(e.Number==51705) {Check(true,"Bloquea reversa unilateral durante envío Zeus");}
        await repository.FinishAsync(2,jobId,"CONTABILIZADO","01","0100000001",null,default);
        q.CommandText="SELECT Estado FROM core.ZeusEnvio WHERE ZeusEnvioId="+jobId;
        Check((string)(await q.ExecuteScalarAsync())! == "ENVIANDO","No confirma resultado de otra empresa");
        await repository.FinishAsync(1,jobId,"RECHAZADO",null,null,"Prueba",default);
        Check(await repository.ApproveAsync(1,20,1,approve,default)==jobId,"Rechazo confirmado permite nueva aprobación");
        await repository.ClaimAsync(default);
        q.CommandText="UPDATE core.ZeusEnvio SET ActualizadoEnUtc=DATEADD(minute,-20,SYSUTCDATETIME()) WHERE ZeusEnvioId="+jobId;await q.ExecuteNonQueryAsync();
        Check(await repository.ClaimAsync(default) is null,"Un envío abandonado no vuelve a la cola");
        q.CommandText="SELECT Estado FROM core.ZeusEnvio WHERE ZeusEnvioId="+jobId;
        Check((string)(await q.ExecuteScalarAsync())! == "INCIERTO","Envío abandonado exige conciliación");
        await WarehouseAccountsTests.Run(cs,settings,source,input,Check);
        await CompanySecurityTests.Run(cs,dir!.FullName,Check);
        await SupplierSendTests.Run(cs,Check);
        var identityJournal=testJournal with{Proveedor=new(10,"901528333","901528333")};
        Check((await transport.SendAsync(1,identityJournal,Guid.NewGuid(),default)).Estado=="RECHAZADO","Contabilización rechaza proveedor inexistente sin crearlo");
        q.CommandText="INSERT dbo.TERCEROS VALUES('901528333','Prueba',0);INSERT dbo.PROVEEDORES VALUES('901528333','901528333','Prueba',1,'901528333')";await q.ExecuteNonQueryAsync();
        Check((await transport.SendAsync(1,identityJournal,Guid.NewGuid(),default)).Estado=="RECHAZADO","Contabilización rechaza proveedor deshabilitado");
        q.CommandText="UPDATE dbo.PROVEEDORES SET Deshabilitado=0 WHERE IDPROVE='901528333';UPDATE dbo.TestMode SET Mode='OK';DELETE dbo.TRANSAC;DELETE dbo.DOCUMENT";await q.ExecuteNonQueryAsync();
        Check((await transport.SendAsync(1,identityJournal,Guid.NewGuid(),default)).Estado=="CONTABILIZADO","Contabiliza con tercero y proveedor existentes de igual identificación");
        await SupplierSyncTests.Run(cs,dir!.FullName,Check);
        await AutomaticPostingTests.Sql(cs,settings,Check);
    }
    finally
    {
        SqlConnection.ClearAllPools();setup.CommandText=$"ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{db}]";await setup.ExecuteNonQueryAsync();
    }
}
Console.WriteLine($"{count} comprobaciones Zeus correctas.");
