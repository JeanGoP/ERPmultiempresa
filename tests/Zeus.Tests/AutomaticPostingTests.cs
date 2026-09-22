using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using NexoERP.Api.Data;
using NexoERP.Api.Purchasing;
using NexoERP.Api.Zeus;

static class AutomaticPostingTests
{
    private const string Xml="""
        <Invoice xmlns="urn:test"><InvoiceLine><ID>1</ID><TaxTotal><TaxSubtotal><TaxableAmount>100</TaxableAmount><TaxAmount>19</TaxAmount><TaxCategory><Percent>19</Percent><TaxScheme><ID>01</ID><Name>IVA</Name></TaxScheme></TaxCategory></TaxSubtotal></TaxTotal></InvoiceLine><WithholdingTaxTotal><TaxSubtotal><TaxableAmount>100</TaxableAmount><TaxAmount>2.5</TaxAmount><TaxCategory><Percent>2.5</Percent><TaxScheme><ID>06</ID><Name>Retefuente</Name></TaxScheme></TaxCategory></TaxSubtotal></WithholdingTaxTotal></Invoice>
        """;
    public static void Unit(Action<bool,string> check)
    {
        var map=new Dictionary<string,long?>{{"1",2}};
        var parsed=ZeusXmlTaxes.Parse(Xml,map,2.5m);
        check(parsed.Impuestos.Single()==new ZeusTax("IVA",19,100,19,2),"Impuesto XML conserva concepto, tarifa, base, valor y bodega de línea");
        check(parsed.Retenciones.Single()==new ZeusTax("RETEFUENTE",2.5m,100,2.5m),"Retención XML se obtiene sin recaptura");
        check(ZeusXmlTaxes.Parse("<AttachedDocument><Attachment><ExternalReference><Description><![CDATA["+Xml+"]]></Description></ExternalReference></Attachment></AttachedDocument>",map,2.5m).Impuestos.Single().Valor==19,"Contenedor AttachedDocument usa factura embebida");
        check(ZeusXmlTaxes.Parse(Xml.Replace("<Percent>19</Percent>",""),map,2.5m).Impuestos.Single().Tarifa==19,"Tarifa ausente se deriva de base y valor XML");
        check(ZeusXmlTaxes.Parse(Xml.Replace("Retefuente","Autorretención"),map,0).Retenciones.Length==0,"No envía autorretenciones XML a Zeus");
        check(ZeusXmlTaxes.Parse(Xml,map,0).Retenciones.Length==0,"Retención anulada en ERP no se reaplica desde XML");
        foreach(var action in new Action[]{()=>ZeusXmlTaxes.Parse(Xml,new Dictionary<string,long?>(),2.5m),()=>ZeusXmlTaxes.Parse(Xml,map,3),()=>ZeusXmlTaxes.Parse("<!DOCTYPE Invoice [<!ENTITY x SYSTEM 'file:///secret'>]><Invoice>&x;</Invoice>",map,0)})
        {try{action();throw new Exception("Aceptó desglose inseguro");}catch(ArgumentException){check(true,"Rechaza XML incoherente, retención ajustada sin desglose o entidades externas");}}
    }
    public static async Task Sql(string cs,ZeusSettings settings,Action<bool,string> check)
    {
        await using var c=new SqlConnection(cs);await c.OpenAsync();await using var q=c.CreateCommand();
        q.CommandText="EXEC sys.sp_set_session_context @key=N'EmpresaId',@value=1;DELETE core.ZeusEnvio;UPDATE core.ZeusConfiguracion SET Configuracion=@J WHERE EmpresaId=1;UPDATE comp.DocumentoProveedor SET XmlOriginal=@Xml WHERE EmpresaId=1 AND DocumentoProveedorId=100;UPDATE inv.RecepcionMercancia SET Estado='VALIDADA' WHERE EmpresaId=1 AND RecepcionMercanciaId=20";
        q.Parameters.AddWithValue("@J",JsonSerializer.Serialize(settings));q.Parameters.AddWithValue("@Xml",Xml);await q.ExecuteNonQueryAsync();q.Parameters.Clear();
        q.CommandText="""
            CREATE PROCEDURE inv.usp_ContabilizarRecepcion @EmpresaId bigint,@RecepcionMercanciaId bigint,@UsuarioId bigint,@CorrelationId uniqueidentifier=NULL,@BodegasJson nvarchar(max)=NULL,@FechaContableSolicitada date=NULL AS
            BEGIN
              SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
              DECLARE @Existing bit=0;
              IF EXISTS(SELECT 1 FROM inv.RecepcionMercancia WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId AND Estado='CONTABILIZADA') SET @Existing=1;
              UPDATE inv.RecepcionMercancia SET Estado='CONTABILIZADA' WHERE EmpresaId=@EmpresaId AND RecepcionMercanciaId=@RecepcionMercanciaId;
              COMMIT; SELECT @RecepcionMercanciaId,CONVERT(varchar(15),'CONTABILIZADA'),1,@Existing;
            END
            """;await q.ExecuteNonQueryAsync();
        var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{{"ConnectionStrings:NexoErp",cs}}).Build();
        var factory=new TenantConnectionFactory(config);var purchasing=new PurchasingRepository(factory);var repo=new ZeusRepository(factory);
        var result=await purchasing.PostReceiptAsync(1,20,new(1,null),default);
        check(result.Zeus?.Estado=="PENDIENTE","Contabilizar ERP encola automáticamente Zeus en la misma acción");
        q.CommandText="SELECT Snapshot FROM core.ZeusEnvio WHERE EmpresaId=1 AND RecepcionMercanciaId=20";
        var snapshot=JsonSerializer.Deserialize<ZeusSnapshot>((string)(await q.ExecuteScalarAsync())!)!;
        check(snapshot.Movimientos.Sum(m=>m.Valor)==0&&snapshot.Movimientos.Any(m=>m.Regla.Concepto=="IVA"&&m.Valor==19),"Comprobante automático cuadra con impuestos XML");
        q.CommandText="DELETE core.ZeusEnvio;UPDATE core.ZeusConfiguracion SET Configuracion=@Routes WHERE EmpresaId=1";
        var routed=settings with{FuentesAutomaticas=[new("Norte","ENTRADA_MERCANCIA","13","01",[1],UnidadNegocio:"NORTE",TipoFactura:"FC")]};
        q.Parameters.AddWithValue("@Routes",JsonSerializer.Serialize(routed));await q.ExecuteNonQueryAsync();q.Parameters.Clear();
        check((await repo.RetryAutomaticAsync(1,20,1,default)).Estado=="PENDIENTE","Entrada usa fuente automática de su sucursal");
        q.CommandText="SELECT Snapshot FROM core.ZeusEnvio WHERE EmpresaId=1 AND RecepcionMercanciaId=20";
        var routedSnapshot=JsonSerializer.Deserialize<ZeusSnapshot>((string)(await q.ExecuteScalarAsync())!)!;
        check(routedSnapshot.Configuracion.Fuente=="13"&&routedSnapshot.Configuracion.Serie=="01"&&routedSnapshot.Configuracion.SucursalOperacion=="Norte","Fuente, serie y sucursal quedan guardadas en el comprobante");
        check(await repo.EligibleAsync(1,routedSnapshot,default),"Worker sin sesión de usuario valida la fuente congelada");
        q.CommandText="UPDATE core.ZeusEnvio SET Estado='RECHAZADO';UPDATE core.ZeusConfiguracion SET Configuracion=@Routes WHERE EmpresaId=1";
        q.Parameters.AddWithValue("@Routes",JsonSerializer.Serialize(settings));await q.ExecuteNonQueryAsync();q.Parameters.Clear();
        check((await repo.RetryAutomaticAsync(1,20,2,default)).Estado=="PENDIENTE","Otro operador puede recuperar sin cambiar la fuente original");
        q.CommandText="SELECT Snapshot FROM core.ZeusEnvio WHERE EmpresaId=1 AND RecepcionMercanciaId=20";
        var retried=JsonSerializer.Deserialize<ZeusSnapshot>((string)(await q.ExecuteScalarAsync())!)!;
        check(retried.Configuracion.Fuente=="13"&&retried.Configuracion.Serie=="01","Cambiar configuración no redirige comprobantes ya preparados");
        check(retried.Configuracion.UnidadNegocio=="NORTE"&&retried.Configuracion.TipoFactura=="FC","Reintento conserva unidad de negocio y tipo originales pese a cambios generales");
        check(await repo.EligibleAsync(1,retried,default),"Reintento con fuente original sigue siendo elegible");
        try{await repo.SaveSettingsAsync(1,1,new(1,settings with{FuentesAutomaticas=[new("Ajena","ENTRADA_MERCANCIA","14","00",[999999])]}),default);throw new Exception("Aceptó usuario ajeno");}
        catch(ArgumentException){check(true,"Configuración rechaza sucursal inexistente antes de guardar");}
        check((await purchasing.PostReceiptAsync(1,20,new(1,null),default)).YaExistia,"Repetición de botón no duplica contabilización ERP");
        q.CommandText="SELECT COUNT(*) FROM core.ZeusEnvio WHERE EmpresaId=1 AND RecepcionMercanciaId=20";check(Convert.ToInt32(await q.ExecuteScalarAsync())==1,"Una sola cola Zeus por entrada");
        q.CommandText="UPDATE core.ZeusEnvio SET Estado='INCIERTO'";await q.ExecuteNonQueryAsync();
        check((await repo.RetryAutomaticAsync(1,20,1,default)).Estado=="INCIERTO","Recuperación automática no reenvía resultados inciertos");
        try{await repo.RetryAutomaticAsync(2,20,1,default);throw new Exception("Aceptó empresa ajena");}catch(ArgumentException){check(true,"Recuperación no cruza empresas");}
        q.CommandText="UPDATE core.ZeusEnvio SET Estado='RECHAZADO';UPDATE comp.DocumentoProveedor SET XmlOriginal=NULL WHERE EmpresaId=1 AND DocumentoProveedorId=100";await q.ExecuteNonQueryAsync();
        check((await repo.RetryAutomaticAsync(1,20,1,default)).Estado=="REQUIERE_REVISION","Falta de XML queda visible sin inventar impuestos ni repetir ERP");
        q.CommandText="DELETE core.ZeusEnvio;UPDATE inv.RecepcionMercancia SET Estado='VALIDADA';UPDATE comp.DocumentoProveedor SET XmlOriginal=@Xml WHERE EmpresaId=1 AND DocumentoProveedorId=100";q.Parameters.AddWithValue("@Xml",Xml);await q.ExecuteNonQueryAsync();q.Parameters.Clear();
        try{await repo.RetryAutomaticAsync(1,20,1,default);throw new Exception("Envió borrador");}catch(ArgumentException){check(true,"Guardar borrador no genera envío contable Zeus");}
        q.CommandText="CREATE TRIGGER core.TestRejectAutomatic ON core.ZeusEnvio AFTER UPDATE AS BEGIN IF EXISTS(SELECT 1 FROM inserted WHERE Estado='PENDIENTE') THROW 51995,'Fallo de cola simulado',1; END";await q.ExecuteNonQueryAsync();
        try{await purchasing.PostReceiptAsync(1,20,new(1,null),default);throw new Exception("Confirmó cola fallida");}catch(SqlException e)when(e.Number==51995){check(true,"Fallo SQL al guardar cola revierte contabilización ERP");}
        q.CommandText="SELECT COUNT(*) FROM core.ZeusEnvio";check(Convert.ToInt32(await q.ExecuteScalarAsync())==0,"Rollback no deja trabajo Zeus huérfano");
        q.CommandText="SELECT Estado FROM inv.RecepcionMercancia WHERE RecepcionMercanciaId=20";check((string)(await q.ExecuteScalarAsync())! == "VALIDADA","Rollback conserva entrada sin contabilizar");
    }
}
