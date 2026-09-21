using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.MasterData;

namespace NexoERP.Api.Zeus;

public sealed record ZeusSupplierSendRequest(string Zona="",string Segmento="",string CategoriaFiscal="",string Nombre1="",string Apellido1="",string Huella="");
public sealed record ZeusSupplierSendResult(string Estado,string Codigo,string Mensaje);

public sealed partial class ZeusTransport
{
    public static string SupplierFingerprint(ZeusSettings settings,SupplierResponse supplier)=>Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new{settings,supplier}))));
    internal static string IdentificationCode(string type)=>type switch {
        "NIT"=>"31","CC"=>"13","CE"=>"22","RC"=>"11","TI"=>"12","TE"=>"21","PAS"=>"41","DE"=>"42","OTRO"=>"00",
        _=>throw new ArgumentException("El tipo de identificación no tiene equivalencia confirmada en Zeus.")};

    internal static string PersonType(SupplierResponse s)
    {
        if(string.IsNullOrWhiteSpace(s.DatosXmlJson))return "";
        try {
            using var doc=JsonDocument.Parse(s.DatosXmlJson);var root=doc.RootElement;
            if(root.ValueKind!=JsonValueKind.Object)return "";
            string Value(JsonElement e,string name)=>e.TryGetProperty(name,out var v)&&v.ValueKind==JsonValueKind.String?v.GetString()!:"";
            string result="";
            if(root.TryGetProperty("NexoPersonConfirmation",out var confirmation)&&confirmation.ValueKind==JsonValueKind.Object
                &&Value(confirmation,"identification")==s.NumeroIdentificacion&&Value(confirmation,"identificationType")==s.TipoIdentificacion)
                result=Value(confirmation,"type");
            else if(root.TryGetProperty("AdditionalAccountID",out var values)&&values.ValueKind==JsonValueKind.Array) {
                var codes=values.EnumerateArray().Where(v=>v.ValueKind==JsonValueKind.Object).Select(v=>Value(v,"value").Trim()).Distinct().ToArray();
                if(codes.Length==1)result=codes[0] switch {"1"=>"J","2"=>"N",_=>""};
            }
            return result is "J" or "N" && !(s.TipoIdentificacion=="CC"&&result=="J")?result:"";
        } catch(JsonException){return "";}
    }
    private static void SupplierText(string? text,string field,int max,bool required=true)
    {
        if((required&&string.IsNullOrWhiteSpace(text))||(text?.Length??0)>max||(text?.Any(char.IsControl)??false))
            throw new ArgumentException($"Revisa {field}: {(required?"obligatorio, ":"")}máximo {max} caracteres. No se recortan datos.");
    }
    private static void SupplierCode(SupplierResponse s)
    {
        if(!s.Activo)throw new ArgumentException("El proveedor del ERP está inactivo.");
        SupplierText(s.NumeroIdentificacion,"identificación sin dígito de verificación",10);
        if(s.NumeroIdentificacion.Any(c=>!char.IsAsciiLetterOrDigit(c)))throw new ArgumentException("La identificación debe estar sin espacios, puntos ni guiones; revisa el maestro del ERP.");
    }
    // Se busca también por el tercero: un proveedor con otro código no debe duplicarse.
    private static async Task<(bool Third,bool Supplier)> SupplierExists(SqlConnection c,SqlTransaction? tx,string id,CancellationToken ct)
    {
        await using var q=c.CreateCommand();q.Transaction=tx;q.CommandTimeout=30;
        q.CommandText="SELECT ISNULL(Deshabilitado,0) FROM dbo.TERCEROS WHERE IDTERCERO=@Id; SELECT RTRIM(IDPROVE),RTRIM(IDTERCERO),ISNULL(Deshabilitado,0) FROM dbo.PROVEEDORES WHERE IDPROVE=@Id OR IDTERCERO=@Id;";
        q.Parameters.Add("@Id",SqlDbType.VarChar,25).Value=id;
        await using var r=await q.ExecuteReaderAsync(ct);var third=await r.ReadAsync(ct);
        if(third&&Convert.ToInt32(r.GetValue(0))!=0)throw new ArgumentException("El tercero está deshabilitado en Zeus; revísalo allí.");
        if(third&&await r.ReadAsync(ct))throw new ArgumentException("Identificación de tercero duplicada en Zeus.");
        await r.NextResultAsync(ct);var supplier=await r.ReadAsync(ct);
        if(supplier&&(r.GetString(0)!=id||r.GetString(1)!=id||Convert.ToInt32(r.GetValue(2))!=0))
            throw new ArgumentException("Zeus tiene un proveedor deshabilitado o con códigos diferentes. Revisa el registro existente; no se creará otro.");
        if(supplier&&await r.ReadAsync(ct))throw new ArgumentException("Hay varios proveedores asociados al tercero en Zeus.");
        if(supplier&&!third)throw new ArgumentException("El proveedor de Zeus no tiene su tercero; requiere revisión.");
        return(third,supplier);
    }
    public async Task<object> SupplierPreviewAsync(long company,ZeusSettings settings,SupplierResponse supplier,CancellationToken ct)
    {
        SupplierCode(supplier);
        await using var c=await OpenAsync(company,settings,ct);
        var existing=await SupplierExists(c,null,supplier.NumeroIdentificacion,ct);
        var zones=new List<string>();var segments=new List<string>();var categories=new List<string>();
        if(!existing.Supplier){
            await using var q=c.CreateCommand();q.CommandText="SELECT RTRIM(IDZONA) FROM dbo.MAEZONAS ORDER BY IDZONA; SELECT RTRIM(IDSEGMENTO) FROM dbo.SEGMENTO WHERE TIPOSEGMENTO='D' ORDER BY IDSEGMENTO; SELECT RTRIM(TipoEmpresa) FROM dbo.TiposDeEmpresa ORDER BY TipoEmpresa;";
            await using var r=await q.ExecuteReaderAsync(ct);
            foreach(var list in new[]{zones,segments,categories}){while(await r.ReadAsync(ct))list.Add(r.GetString(0));await r.NextResultAsync(ct);}
        }
        return new {huella=SupplierFingerprint(settings,supplier),baseDatos=settings.BaseEsperada,codigo=supplier.NumeroIdentificacion,nombre=supplier.RazonSocial,
            divisionPolitica=supplier.DivisionPoliticaZeus,tipoPersona=PersonType(supplier),terceroExiste=existing.Third,proveedorExiste=existing.Supplier,zonas=zones,segmentos=segments,categoriasFiscales=categories};
    }
    public async Task<ZeusSupplierSendResult> SendSupplierAsync(long company,ZeusSettings settings,SupplierResponse s,ZeusSupplierSendRequest input,CancellationToken ct)
    {
        SupplierCode(s);
        await using var c=await OpenAsync(company,settings,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        bool committing=false;
        try {
            await using var q=c.CreateCommand();q.Transaction=tx;q.CommandTimeout=90;
            q.CommandText="SET XACT_ABORT ON; DECLARE @R int; EXEC @R=sys.sp_getapplock @Resource=@Lock,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000; IF @R<0 THROW 51750,'No fue posible bloquear el proveedor.',1;";
            q.Parameters.AddWithValue("@Lock","NexoERP.Zeus.Proveedor:"+s.NumeroIdentificacion);await q.ExecuteNonQueryAsync(ct);q.Parameters.Clear();
            var existing=await SupplierExists(c,tx,s.NumeroIdentificacion,ct);
            if(existing.Supplier){await tx.RollbackAsync(CancellationToken.None);return new("EXISTENTE",s.NumeroIdentificacion,"El tercero y el proveedor ya existen en Zeus. No se modificaron.");}
            SupplierText(s.RazonSocial,"razón social",250);SupplierText(s.Direccion,"dirección",250);SupplierText(s.Ciudad,"ciudad",40);
            SupplierText(s.Telefono,"teléfono",25,false);SupplierText(s.Correo,"correo",60,false);SupplierText(s.SitioWeb,"sitio web",60,false);
            SupplierText(s.ContactoNombre,"nombre de contacto",40,false);
            SupplierText(s.DivisionPoliticaZeus,"división política Zeus",25);SupplierText(settings.UsuarioZeus,"usuario de Zeus",15);
            SupplierText(input.Zona,"zona Zeus",3);SupplierText(input.Segmento,"segmento Zeus",16);
            var person=PersonType(s);var identification="";
            if(!existing.Third){
                identification=IdentificationCode(s.TipoIdentificacion);
                if(person=="")throw new ArgumentException("Confirma el tipo de persona en Editar proveedor antes de enviarlo.");
                SupplierText(input.CategoriaFiscal,"categoría fiscal Zeus",5);
                SupplierText(s.DigitoVerificacion,"dígito de verificación",5,false);
                if(person=="N"){SupplierText(input.Nombre1,"nombres de la persona natural",60);SupplierText(input.Apellido1,"apellidos de la persona natural",60);}
            }
            var account=settings.Cuentas.Where(a=>a.Concepto=="PROVEEDOR"&&a.ArticuloId is null&&a.Tarifa is null&&(a.ProveedorId is null||a.ProveedorId==s.TerceroId))
                .OrderByDescending(a=>a.ProveedorId.HasValue).FirstOrDefault()?.Cuenta;
            SupplierText(account,"cuenta PROVEEDOR en la configuración de Zeus",16);
            q.CommandText="""
                IF NOT EXISTS(SELECT 1 FROM dbo.DIVPOLITICA WHERE IDDIVPOLITICA=@Division AND TIPODIVPOLITICA='D') THROW 51751,'Division politica no existe en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.MAEZONAS WHERE IDZONA=@Zona) THROW 51752,'Zona no existe en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.SEGMENTO WHERE IDSEGMENTO=@Segmento AND TIPOSEGMENTO='D') THROW 51753,'Segmento no existe en Zeus.',1;
                IF NOT EXISTS(SELECT 1 FROM dbo.MAECONT WHERE CODICTA=@Cuenta AND TIPOCTA='D' AND INDCPICTA=3 AND HABILITARCTA=1) THROW 51754,'Cuenta de proveedor no habilitada en Zeus.',1;
                IF @CrearTercero=1 BEGIN
                    IF NOT EXISTS(SELECT 1 FROM dbo.TipoIdentificacion WHERE Codigo=@TipoId) THROW 51755,'Tipo de identificacion no existe en Zeus.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.TiposDeEmpresa WHERE TipoEmpresa=@Fiscal) THROW 51756,'Categoria fiscal no existe en Zeus.',1;
                END;
                """;
            q.Parameters.AddWithValue("@Division",s.DivisionPoliticaZeus!);q.Parameters.AddWithValue("@Zona",input.Zona);q.Parameters.AddWithValue("@Segmento",input.Segmento);
            q.Parameters.AddWithValue("@Cuenta",account!);q.Parameters.AddWithValue("@CrearTercero",!existing.Third);q.Parameters.AddWithValue("@TipoId",identification);q.Parameters.AddWithValue("@Fiscal",input.CategoriaFiscal??"");
            await q.ExecuteNonQueryAsync(ct);
            async Task Call(string procedure,Dictionary<string,object?> parameters){
                await using var cmd=c.CreateCommand();cmd.Transaction=tx;cmd.CommandTimeout=90;cmd.CommandType=CommandType.StoredProcedure;cmd.CommandText=procedure;
                foreach(var (name,value) in parameters)cmd.Parameters.AddWithValue(name,value??DBNull.Value);
                cmd.Parameters.AddWithValue("@Op","I");cmd.Parameters.AddWithValue("@ManejaTransaccionalidad","N");
                var result=cmd.Parameters.Add("@RETURN_VALUE",SqlDbType.Int);result.Direction=ParameterDirection.ReturnValue;
                await using(var reader=await cmd.ExecuteReaderAsync(ct))do{while(await reader.ReadAsync(ct)){}}while(await reader.NextResultAsync(ct));
                if(result.Value is not int code||code!=0)throw new ArgumentException($"{procedure} rechazó la creación. No se confirmó el envío.");
            }
            Dictionary<string,object?> Common()=>new(){["@IDTERCERO"]=s.NumeroIdentificacion,["@DIRECCION"]=s.Direccion,["@CIUDAD"]=s.Ciudad,["@TELEFONO"]=s.Telefono??"",["@EMAIL"]=s.Correo??"",["@DIVPOLITICA"]=s.DivisionPoliticaZeus,["@CODIGODANE"]=s.CiudadCodigo,["@SEGMENTO"]=input.Segmento,["@Usuario"]=settings.UsuarioZeus,["@Tipo"]="N",["@Deshabilitado"]=0};
            if(!existing.Third){
                var p=Common();p["@NOMBRETER"]=s.RazonSocial;p["@TIPOTERCE"]=person;p["@TipoIdentificacion"]=identification;p["@DIGIVERIf"]=s.DigitoVerificacion??"";p["@TIPOEMPRESA"]=input.CategoriaFiscal;
                if(person=="N"){p["@Nombre1"]=input.Nombre1;p["@Apellido1"]=input.Apellido1;}
                await Call("dbo.spMae_Terceros",p);
            }
            var supplier=Common();supplier["@IDPROVE"]=s.NumeroIdentificacion;supplier["@RAZONCIAL"]=s.RazonSocial;supplier["@IDZONA"]=input.Zona;supplier["@CODICTA"]=account;
            supplier["@WEBSITE"]=s.SitioWeb??"";supplier["@CONTACTO"]=s.ContactoNombre??"";supplier["@DIPLAZO"]=(short)0;supplier["@CUPOCRE"]=0m;
            await Call("dbo.spMae_Proveedores",supplier);
            var verified=await SupplierExists(c,tx,s.NumeroIdentificacion,ct);
            if(!verified.Third||!verified.Supplier)throw new ArgumentException("Zeus no creó los registros esperados; se revierte la operación.");
            committing=true;await tx.CommitAsync(ct);
            return new("CREADO",s.NumeroIdentificacion,"Proveedor confirmado en Zeus. No se contabilizó ninguna factura.");
        } catch(Exception error) when(error is SqlException or ArgumentException or InvalidOperationException or OperationCanceledException){
            var uncertain=committing;
            if(!committing)try{await tx.RollbackAsync(CancellationToken.None);}catch{uncertain=true;}
            var message=error is ArgumentException?error.Message:error is SqlException sql&&sql.Number is >=51751 and <=51756?sql.Message:error is SqlException business&&business.Number==50000?"Zeus: "+business.Message[..Math.Min(500,business.Message.Length)]:"Zeus rechazó o interrumpió la creación. Revisa permisos, datos y procedimientos con soporte.";
            return new(uncertain?"INCIERTO":"RECHAZADO",s.NumeroIdentificacion,uncertain?"No se pudo confirmar el resultado. Consulta de nuevo el proveedor en Zeus antes de otro intento.":message);
        }
    }
}
