SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='042_supplier_complete_data')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    ALTER TABLE ter.Tercero ADD
        NombreComercial nvarchar(200) NULL,
        CodigoResponsabilidadFiscal nvarchar(100) NULL,
        RegimenFiscalCodigo nvarchar(20) NULL,
        RegimenFiscalNombre nvarchar(100) NULL,
        Direccion nvarchar(300) NULL,
        CiudadCodigo nvarchar(20) NULL,
        Ciudad nvarchar(100) NULL,
        DepartamentoCodigo nvarchar(20) NULL,
        Departamento nvarchar(100) NULL,
        CodigoPostal nvarchar(20) NULL,
        PaisCodigo nvarchar(10) NULL,
        Pais nvarchar(100) NULL,
        ContactoNombre nvarchar(150) NULL,
        Telefono nvarchar(50) NULL,
        Correo nvarchar(254) NULL,
        SitioWeb nvarchar(300) NULL,
        DatosXmlJson nvarchar(max) NULL,
        ActualizadoEnUtc datetime2(7) NULL;

    EXEC(N'ALTER TABLE ter.Tercero ADD CONSTRAINT CK_Tercero_DatosXmlJson CHECK(DatosXmlJson IS NULL OR ISJSON(DatosXmlJson)=1);');

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('042_supplier_complete_data',N'Datos completos del proveedor desde XML y edición desde maestros');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE ter.usp_GuardarProveedor
    @EmpresaId bigint,
    @TipoIdentificacion varchar(10),
    @NumeroIdentificacion nvarchar(30),
    @DigitoVerificacion char(1)=NULL,
    @RazonSocial nvarchar(200),
    @UsuarioId bigint,
    @TerceroId bigint=NULL,
    @NombreComercial nvarchar(200)=NULL,
    @CodigoResponsabilidadFiscal nvarchar(100)=NULL,
    @RegimenFiscalCodigo nvarchar(20)=NULL,
    @RegimenFiscalNombre nvarchar(100)=NULL,
    @Direccion nvarchar(300)=NULL,
    @CiudadCodigo nvarchar(20)=NULL,
    @Ciudad nvarchar(100)=NULL,
    @DepartamentoCodigo nvarchar(20)=NULL,
    @Departamento nvarchar(100)=NULL,
    @CodigoPostal nvarchar(20)=NULL,
    @PaisCodigo nvarchar(10)=NULL,
    @Pais nvarchar(100)=NULL,
    @ContactoNombre nvarchar(150)=NULL,
    @Telefono nvarchar(50)=NULL,
    @Correo nvarchar(254)=NULL,
    @SitioWeb nvarchar(300)=NULL,
    @DatosXmlJson nvarchar(max)=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @TipoIdentificacion=UPPER(LTRIM(RTRIM(@TipoIdentificacion)));
    SET @NumeroIdentificacion=LTRIM(RTRIM(@NumeroIdentificacion));
    SET @RazonSocial=LTRIM(RTRIM(@RazonSocial));
    IF NULLIF(@NumeroIdentificacion,N'') IS NULL THROW 52000,'La identificacion del proveedor es obligatoria.',1;
    IF NULLIF(@RazonSocial,N'') IS NULL THROW 52001,'La razon social del proveedor es obligatoria.',1;
    IF @DatosXmlJson IS NOT NULL AND ISJSON(@DatosXmlJson)<>1 THROW 52009,'Los datos originales del XML no tienen un formato JSON valido.',1;

    BEGIN TRANSACTION;
    DECLARE @Id bigint,@Creado bit=0,@EdicionManual bit=CASE WHEN @TerceroId IS NULL THEN 0 ELSE 1 END;
    IF @TerceroId IS NOT NULL
        SELECT @Id=TerceroId FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND EsProveedor=1;
    ELSE
        SELECT @Id=TerceroId FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TipoIdentificacion=@TipoIdentificacion AND NumeroIdentificacion=@NumeroIdentificacion;

    IF @TerceroId IS NOT NULL AND @Id IS NULL THROW 52010,'El proveedor no existe en esta empresa.',1;

    IF @Id IS NULL
    BEGIN
        INSERT ter.Tercero
        (
            EmpresaId,TipoIdentificacion,NumeroIdentificacion,DigitoVerificacion,RazonSocial,EsProveedor,
            NombreComercial,CodigoResponsabilidadFiscal,RegimenFiscalCodigo,RegimenFiscalNombre,Direccion,
            CiudadCodigo,Ciudad,DepartamentoCodigo,Departamento,CodigoPostal,PaisCodigo,Pais,ContactoNombre,
            Telefono,Correo,SitioWeb,DatosXmlJson,ActualizadoEnUtc
        )
        VALUES
        (
            @EmpresaId,@TipoIdentificacion,@NumeroIdentificacion,@DigitoVerificacion,@RazonSocial,1,
            NULLIF(LTRIM(RTRIM(@NombreComercial)),N''),NULLIF(LTRIM(RTRIM(@CodigoResponsabilidadFiscal)),N''),
            NULLIF(LTRIM(RTRIM(@RegimenFiscalCodigo)),N''),NULLIF(LTRIM(RTRIM(@RegimenFiscalNombre)),N''),NULLIF(LTRIM(RTRIM(@Direccion)),N''),
            NULLIF(LTRIM(RTRIM(@CiudadCodigo)),N''),NULLIF(LTRIM(RTRIM(@Ciudad)),N''),NULLIF(LTRIM(RTRIM(@DepartamentoCodigo)),N''),
            NULLIF(LTRIM(RTRIM(@Departamento)),N''),NULLIF(LTRIM(RTRIM(@CodigoPostal)),N''),NULLIF(LTRIM(RTRIM(@PaisCodigo)),N''),
            NULLIF(LTRIM(RTRIM(@Pais)),N''),NULLIF(LTRIM(RTRIM(@ContactoNombre)),N''),NULLIF(LTRIM(RTRIM(@Telefono)),N''),
            NULLIF(LTRIM(RTRIM(@Correo)),N''),NULLIF(LTRIM(RTRIM(@SitioWeb)),N''),@DatosXmlJson,SYSUTCDATETIME()
        );
        SET @Id=SCOPE_IDENTITY(); SET @Creado=1;
    END
    ELSE
    BEGIN
        UPDATE ter.Tercero SET
            TipoIdentificacion=@TipoIdentificacion,NumeroIdentificacion=@NumeroIdentificacion,
            DigitoVerificacion=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@DigitoVerificacion)),'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@DigitoVerificacion)),''),DigitoVerificacion) END,
            RazonSocial=@RazonSocial,EsProveedor=1,Activo=1,
            NombreComercial=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@NombreComercial)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@NombreComercial)),N''),NombreComercial) END,
            CodigoResponsabilidadFiscal=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@CodigoResponsabilidadFiscal)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@CodigoResponsabilidadFiscal)),N''),CodigoResponsabilidadFiscal) END,
            RegimenFiscalCodigo=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@RegimenFiscalCodigo)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@RegimenFiscalCodigo)),N''),RegimenFiscalCodigo) END,
            RegimenFiscalNombre=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@RegimenFiscalNombre)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@RegimenFiscalNombre)),N''),RegimenFiscalNombre) END,
            Direccion=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@Direccion)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@Direccion)),N''),Direccion) END,
            CiudadCodigo=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@CiudadCodigo)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@CiudadCodigo)),N''),CiudadCodigo) END,
            Ciudad=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@Ciudad)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@Ciudad)),N''),Ciudad) END,
            DepartamentoCodigo=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@DepartamentoCodigo)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@DepartamentoCodigo)),N''),DepartamentoCodigo) END,
            Departamento=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@Departamento)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@Departamento)),N''),Departamento) END,
            CodigoPostal=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@CodigoPostal)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@CodigoPostal)),N''),CodigoPostal) END,
            PaisCodigo=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@PaisCodigo)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@PaisCodigo)),N''),PaisCodigo) END,
            Pais=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@Pais)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@Pais)),N''),Pais) END,
            ContactoNombre=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@ContactoNombre)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@ContactoNombre)),N''),ContactoNombre) END,
            Telefono=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@Telefono)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@Telefono)),N''),Telefono) END,
            Correo=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@Correo)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@Correo)),N''),Correo) END,
            SitioWeb=CASE WHEN @EdicionManual=1 THEN NULLIF(LTRIM(RTRIM(@SitioWeb)),N'') ELSE COALESCE(NULLIF(LTRIM(RTRIM(@SitioWeb)),N''),SitioWeb) END,
            DatosXmlJson=COALESCE(@DatosXmlJson,DatosXmlJson),ActualizadoEnUtc=SYSUTCDATETIME()
        WHERE EmpresaId=@EmpresaId AND TerceroId=@Id;
    END;

    DECLARE @Auditoria nvarchar(max)=(SELECT @NumeroIdentificacion identificacion,@RazonSocial razonSocial,@Ciudad ciudad,@Direccion direccion,@Correo correo,@Telefono telefono FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'PROVEEDOR_CREADO' ELSE 'PROVEEDOR_ACTUALIZADO' END,'ter.Tercero',CONVERT(nvarchar(100),@Id),@Auditoria,'MAESTROS');
    COMMIT; SELECT @Id TerceroId,@Creado Creado;
END;
GO
