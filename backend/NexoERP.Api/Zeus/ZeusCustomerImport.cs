using System.Data;
using Microsoft.Data.SqlClient;

namespace NexoERP.Api.Zeus;

public sealed record ZeusCustomerSyncResult(string? Cursor,int Procesados,int Creados,int Actualizados,int Omitidos,bool HayMas);

public sealed partial class ZeusHistoricalPortfolio
{
    private sealed record ImportedCustomer(string Id,string Name,string IdentificationType,string? CheckDigit,
        string? FirstNames,string? LastNames,string? Address,string? CityCode,string? City,
        string? DepartmentCode,string? Department,string? CountryCode,string? Country,
        string? Phone,string? Email,string? Seller,string? CustomerType);

    private static string? Trimmed(SqlDataReader reader,int index) => reader.IsDBNull(index)?null:Convert.ToString(reader.GetValue(index))?.Trim();

    public async Task<ZeusCustomerSyncResult> SyncCustomersAsync(long company,string? cursor,long user,CancellationToken ct)
    {
        cursor=cursor?.Trim();
        if(cursor is {Length: >25})throw new ArgumentException("El cursor de sincronización no es válido.");
        const int pageSize=100;
        var source=new List<ImportedCustomer>();
        await using(var zeus=await OpenAsync(company,ct))
        await using(var query=zeus.CreateCommand())
        {
            query.CommandTimeout=60;
            query.CommandText="""
                SELECT TOP (100) RTRIM(t.IDTERCERO),RTRIM(t.NOMBRETER),RTRIM(ISNULL(t.TipoIdentificacion,'')),
                    RTRIM(ISNULL(t.DIGIVERIF,'')),RTRIM(ISNULL(t.Nombre1,'')),RTRIM(ISNULL(t.Nombre2,'')),
                    RTRIM(ISNULL(t.Apellido1,'')),RTRIM(ISNULL(t.Apellido2,'')),
                    RTRIM(COALESCE(NULLIF(t.DIRECCION,''),c.DIRECCION)),
                    RTRIM(COALESCE(NULLIF(t.DIVPOLITICA,''),NULLIF(c.DIVPOLITICA,''),'')),
                    RTRIM(COALESCE(NULLIF(t.CODIGODANE,''),NULLIF(c.CODIGODANE,''),'')),
                    RTRIM(COALESCE(NULLIF(t.CIUDAD,''),c.CIUDAD,d.DESDIVPOLITICA)),
                    RTRIM(ISNULL(p.DESDIVPOLITICA,'')),RTRIM(COALESCE(NULLIF(t.Pais,''),c.Pais)),
                    RTRIM(COALESCE(NULLIF(t.Telefono,''),c.TELEFONO)),RTRIM(COALESCE(NULLIF(t.Email,''),c.EMAIL)),
                    RTRIM(c.IDVENDE),RTRIM(c.TipoCliente)
                FROM dbo.TERCEROS t
                CROSS APPLY (SELECT TOP(1) * FROM dbo.CLIENTES c
                    WHERE c.IDTERCERO=t.IDTERCERO AND ISNULL(c.Deshabilitado,0)=0 ORDER BY c.IDCLIENTE) c
                LEFT JOIN dbo.DIVPOLITICA d ON d.IDDIVPOLITICA=COALESCE(NULLIF(t.DIVPOLITICA,''),NULLIF(c.DIVPOLITICA,''))
                LEFT JOIN dbo.DIVPOLITICA p ON p.IDDIVPOLITICA=LEFT(COALESCE(NULLIF(t.DIVPOLITICA,''),NULLIF(c.DIVPOLITICA,'')),4)
                WHERE t.IDTERCERO>@Cursor AND ISNULL(t.Deshabilitado,0)=0
                ORDER BY t.IDTERCERO;
                """;
            query.Parameters.Add("@Cursor",SqlDbType.VarChar,25).Value=cursor??"";
            await using var reader=await query.ExecuteReaderAsync(ct);
            while(await reader.ReadAsync(ct))
            {
                var division=Trimmed(reader,9);
                var dane=Trimmed(reader,10);
                var cityCode=division is {Length:7} && division.StartsWith("57",StringComparison.Ordinal) && division[2..].All(char.IsAsciiDigit)
                    ?division[2..]:dane is {Length:5} && dane.All(char.IsAsciiDigit)?dane
                    :dane is {Length:7} && dane.StartsWith("57",StringComparison.Ordinal) && dane[2..].All(char.IsAsciiDigit)?dane[2..]:null;
                var first=string.Join(' ',new[]{Trimmed(reader,4),Trimmed(reader,5)}.Where(s=>!string.IsNullOrWhiteSpace(s)));
                var last=string.Join(' ',new[]{Trimmed(reader,6),Trimmed(reader,7)}.Where(s=>!string.IsNullOrWhiteSpace(s)));
                source.Add(new(Trimmed(reader,0)??"",Trimmed(reader,1)??"",Trimmed(reader,2)??"",Trimmed(reader,3),
                    first,last,Trimmed(reader,8),cityCode,Trimmed(reader,11),cityCode is null?null:cityCode[..2],Trimmed(reader,12),
                    cityCode is null?null:"57",cityCode is null?Trimmed(reader,13):"Colombia",
                    Trimmed(reader,14),Trimmed(reader,15),Trimmed(reader,16),Trimmed(reader,17)));
            }
        }
        var created=0;var updated=0;var skipped=0;
        await using var local=await connections.OpenAsync(company,false,ct);
        foreach(var row in source)
        {
            ct.ThrowIfCancellationRequested();
            var type=row.IdentificationType.ToUpperInvariant() switch
            {
                "31" or "NIT"=>"NIT", "13" or "CC"=>"CC",
                "22" or "CE"=>"CE", "11" or "RC"=>"RC", "12" or "TI"=>"TI",
                "21" or "TE"=>"TE", "41" or "PAS"=>"PAS", "42" or "DE"=>"DE",
                "00" or "OTRO"=>"OTRO", _=>null
            };
            if(type is null||row.Id.Length is <1 or >30||row.Name.Length is <1 or >200||
               row.FirstNames?.Length>60||row.LastNames?.Length>60)
            {skipped++;continue;}
            // Cada tercero se confirma por separado: un registro defectuoso no revierte el lote.
            await using var tx=(SqlTransaction)await local.BeginTransactionAsync(IsolationLevel.Serializable,ct);
            await using var q=ZeusRepository.Command(local,"",company,tx);
            void AddOptional(string name,string? value)=>q.Parameters.AddWithValue(name,(object?)value??DBNull.Value);
            ZeusRepository.Add(q,"@Nit",row.Id);ZeusRepository.Add(q,"@Name",row.Name);
            ZeusRepository.Add(q,"@Type",type);ZeusRepository.Add(q,"@Person",type=="NIT"?"J":"N");
            AddOptional("@CheckDigit",row.CheckDigit is {Length:1}?row.CheckDigit:null);
            AddOptional("@First",row.FirstNames);AddOptional("@Last",row.LastNames);
            AddOptional("@Address",row.Address);AddOptional("@CityCode",row.CityCode);
            AddOptional("@City",row.City);AddOptional("@DepartmentCode",row.DepartmentCode);
            AddOptional("@Department",row.Department);AddOptional("@CountryCode",row.CountryCode);
            AddOptional("@Country",row.Country);AddOptional("@Phone",row.Phone);
            AddOptional("@Email",row.Email);AddOptional("@Seller",row.Seller);
            AddOptional("@CustomerType",row.CustomerType);ZeusRepository.Add(q,"@User",user);
            q.CommandText="""
                DECLARE @Id bigint,@ExistingType varchar(10),@New bit=0;
                SELECT TOP(2) @Id=TerceroId,@ExistingType=TipoIdentificacion
                FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND NumeroIdentificacion=@Nit;
                IF (SELECT COUNT(*) FROM ter.Tercero WHERE EmpresaId=@E AND NumeroIdentificacion=@Nit)>1
                    THROW 52320,'Identificación duplicada en Nexo.',1;
                IF @Id IS NOT NULL AND @ExistingType<>@Type
                    THROW 52321,'Tipo de identificación diferente en Nexo.',1;
                IF @Id IS NULL
                BEGIN
                    INSERT ter.Tercero(EmpresaId,TipoIdentificacion,NumeroIdentificacion,DigitoVerificacion,
                        RazonSocial,EsCliente,Direccion,CiudadCodigo,Ciudad,DepartamentoCodigo,Departamento,
                        PaisCodigo,Pais,Telefono,Correo,ActualizadoEnUtc)
                    VALUES(@E,@Type,@Nit,@CheckDigit,@Name,1,@Address,@CityCode,@City,
                        @DepartmentCode,@Department,@CountryCode,@Country,@Phone,@Email,SYSUTCDATETIME());
                    SET @Id=SCOPE_IDENTITY();SET @New=1;
                END
                ELSE
                    UPDATE ter.Tercero SET EsCliente=1,Activo=1,RazonSocial=@Name,
                        DigitoVerificacion=COALESCE(@CheckDigit,DigitoVerificacion),
                        Direccion=COALESCE(NULLIF(@Address,''),Direccion),
                        CiudadCodigo=COALESCE(@CityCode,CiudadCodigo),Ciudad=COALESCE(NULLIF(@City,''),Ciudad),
                        DepartamentoCodigo=COALESCE(@DepartmentCode,DepartamentoCodigo),
                        Departamento=COALESCE(NULLIF(@Department,''),Departamento),
                        PaisCodigo=COALESCE(@CountryCode,PaisCodigo),Pais=COALESCE(NULLIF(@Country,''),Pais),
                        Telefono=COALESCE(NULLIF(@Phone,''),Telefono),Correo=COALESCE(NULLIF(@Email,''),Correo),
                        ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND TerceroId=@Id;
                IF NOT EXISTS(SELECT 1 FROM ven.ClientePerfil WHERE EmpresaId=@E AND TerceroId=@Id)
                    INSERT ven.ClientePerfil(EmpresaId,TerceroId,TipoPersona,Nombre1,Apellido1,VendedorZeus,
                        TipoClienteZeus,ZeusEstado,ZeusMensaje)
                    VALUES(@E,@Id,@Person,NULLIF(@First,''),NULLIF(@Last,''),NULLIF(@Seller,''),
                        NULLIF(@CustomerType,''),'CLIENTE',N'Cliente sincronizado desde Zeus.');
                ELSE
                    UPDATE ven.ClientePerfil SET TipoPersona=@Person,
                        Nombre1=COALESCE(NULLIF(@First,''),Nombre1),Apellido1=COALESCE(NULLIF(@Last,''),Apellido1),
                        VendedorZeus=COALESCE(NULLIF(@Seller,''),VendedorZeus),
                        TipoClienteZeus=COALESCE(NULLIF(@CustomerType,''),TipoClienteZeus),
                        ZeusEstado=CASE WHEN ZeusEstado='ENVIANDO' THEN ZeusEstado ELSE 'CLIENTE' END,
                        ZeusMensaje=CASE WHEN ZeusEstado='ENVIANDO' THEN ZeusMensaje ELSE N'Cliente verificado en Zeus.' END,
                        ZeusActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@E AND TerceroId=@Id;
                INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen)
                VALUES(@E,@User,CASE WHEN @New=1 THEN 'CLIENTE_IMPORTADO_ZEUS' ELSE 'CLIENTE_ACTUALIZADO_ZEUS' END,
                    'ter.Tercero',CONVERT(varchar(30),@Id),'ZEUS');
                SELECT @New;
                """;
            try
            {
                var isNew=Convert.ToBoolean(await q.ExecuteScalarAsync(ct));
                await tx.CommitAsync(ct);if(isNew)created++;else updated++;
            }
            catch(SqlException e) when(e.Number is 2601 or 2627 or 50000 or 52320 or 52321 or 2628 or 8152)
            {
                await tx.RollbackAsync(ct);skipped++;
            }
        }
        return new(source.LastOrDefault()?.Id??cursor,source.Count,created,updated,skipped,source.Count==pageSize);
    }
}
