SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF SCHEMA_ID(N'ven') IS NULL EXEC(N'CREATE SCHEMA ven AUTHORIZATION dbo');
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='061_customer_sales_foundation')
BEGIN
    CREATE TABLE ven.ClientePerfil(
        EmpresaId bigint NOT NULL, TerceroId bigint NOT NULL,
        TipoPersona char(1) NOT NULL, Nombre1 nvarchar(60) NULL, Apellido1 nvarchar(60) NULL,
        VendedorZeus varchar(3) NULL, TipoClienteZeus varchar(3) NULL,
        ZeusEstado varchar(20) NOT NULL DEFAULT 'PENDIENTE',
        ZeusMensaje nvarchar(1500) NULL, ZeusIntentos int NOT NULL DEFAULT 0,
        ZeusIntento uniqueidentifier NOT NULL DEFAULT NEWID(),
        ZeusActualizadoEnUtc datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ClientePerfil PRIMARY KEY(EmpresaId,TerceroId),
        CONSTRAINT FK_ClientePerfil_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT CK_ClientePerfil_Persona CHECK(TipoPersona IN('N','J')),
        CONSTRAINT CK_ClientePerfil_Estado CHECK(ZeusEstado IN('PENDIENTE','ENVIANDO','TERCERO','CLIENTE','RECHAZADO','INCIERTO'))
    );
    DECLARE @Table sysname;
    DECLARE tables CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.tables WHERE schema_id=SCHEMA_ID('ven');
    OPEN tables; FETCH NEXT FROM tables INTO @Table;
    WHILE @@FETCH_STATUS=0
    BEGIN
        EXEC('ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.'+@Table+', ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.'+@Table+' AFTER INSERT, ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ven.'+@Table+' AFTER UPDATE;');
        FETCH NEXT FROM tables INTO @Table;
    END;
    CLOSE tables; DEALLOCATE tables;
    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico) VALUES
      ('MAESTROS.CLIENTE.ADMINISTRAR','MAESTROS','CLIENTE',N'Administrar clientes',0);
    DECLARE @AdminRolId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='ADMIN');
    INSERT seg.RolPermiso(RolId,PermisoId)
      SELECT @AdminRolId,p.PermisoId FROM seg.Permiso p
      WHERE p.Codigo='MAESTROS.CLIENTE.ADMINISTRAR'
      AND NOT EXISTS(SELECT 1 FROM seg.RolPermiso rp WHERE rp.RolId=@AdminRolId AND rp.PermisoId=p.PermisoId);
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('061_customer_sales_foundation',N'Maestro de clientes con sincronización del tercero en Zeus por empresa');
END;
COMMIT;
GO
CREATE OR ALTER PROCEDURE ter.usp_GuardarCliente
    @EmpresaId bigint,@TerceroId bigint=NULL,@TipoIdentificacion varchar(10),@NumeroIdentificacion nvarchar(30),
    @DigitoVerificacion char(1)=NULL,@RazonSocial nvarchar(200),@NombreComercial nvarchar(200)=NULL,
    @CodigoResponsabilidadFiscal nvarchar(100)=NULL,@RegimenFiscalCodigo nvarchar(20)=NULL,@RegimenFiscalNombre nvarchar(100)=NULL,
    @Direccion nvarchar(300)=NULL,@CiudadCodigo nvarchar(20)=NULL,@Ciudad nvarchar(100)=NULL,
    @DepartamentoCodigo nvarchar(20)=NULL,@Departamento nvarchar(100)=NULL,@CodigoPostal nvarchar(20)=NULL,
    @PaisCodigo nvarchar(10)=NULL,@Pais nvarchar(100)=NULL,@ContactoNombre nvarchar(150)=NULL,
    @Telefono nvarchar(50)=NULL,@Correo nvarchar(254)=NULL,@SitioWeb nvarchar(300)=NULL,
    @TipoPersona char(1),@Nombre1 nvarchar(60)=NULL,@Apellido1 nvarchar(60)=NULL,
    @VendedorZeus varchar(3)=NULL,@TipoClienteZeus varchar(3)=NULL,@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @TipoIdentificacion=UPPER(LTRIM(RTRIM(@TipoIdentificacion)));
    SET @NumeroIdentificacion=LTRIM(RTRIM(@NumeroIdentificacion));
    SET @RazonSocial=LTRIM(RTRIM(@RazonSocial));
    IF NULLIF(@NumeroIdentificacion,N'') IS NULL OR NULLIF(@RazonSocial,N'') IS NULL THROW 52200,'Identificacion y nombre del cliente son obligatorios.',1;
    IF @TipoPersona NOT IN('N','J') OR (@TipoIdentificacion='NIT' AND @TipoPersona<>'J') OR (@TipoIdentificacion='CC' AND @TipoPersona<>'N')
        THROW 52201,'Tipo de persona incompatible con la identificacion.',1;
    IF @TipoPersona='N' AND (NULLIF(LTRIM(RTRIM(@Nombre1)),N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Apellido1)),N'') IS NULL)
        THROW 52202,'Nombres y apellidos son obligatorios para persona natural en Zeus.',1;
    BEGIN TRANSACTION;
    DECLARE @Id bigint,@Creado bit=0;
    IF @TerceroId IS NOT NULL
        SELECT @Id=TerceroId FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND EsCliente=1;
    ELSE
        SELECT @Id=TerceroId FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TipoIdentificacion=@TipoIdentificacion AND NumeroIdentificacion=@NumeroIdentificacion;
    IF @TerceroId IS NOT NULL AND @Id IS NULL THROW 52203,'El cliente no existe en esta empresa.',1;
    IF @Id IS NULL
    BEGIN
        INSERT ter.Tercero(EmpresaId,TipoIdentificacion,NumeroIdentificacion,DigitoVerificacion,RazonSocial,EsCliente,
            NombreComercial,CodigoResponsabilidadFiscal,RegimenFiscalCodigo,RegimenFiscalNombre,Direccion,CiudadCodigo,Ciudad,
            DepartamentoCodigo,Departamento,CodigoPostal,PaisCodigo,Pais,ContactoNombre,Telefono,Correo,SitioWeb,ActualizadoEnUtc)
        VALUES(@EmpresaId,@TipoIdentificacion,@NumeroIdentificacion,@DigitoVerificacion,@RazonSocial,1,
            @NombreComercial,@CodigoResponsabilidadFiscal,@RegimenFiscalCodigo,@RegimenFiscalNombre,@Direccion,@CiudadCodigo,@Ciudad,
            @DepartamentoCodigo,@Departamento,@CodigoPostal,@PaisCodigo,@Pais,@ContactoNombre,@Telefono,@Correo,@SitioWeb,SYSUTCDATETIME());
        SET @Id=SCOPE_IDENTITY(); SET @Creado=1;
    END
    ELSE
        UPDATE ter.Tercero SET TipoIdentificacion=@TipoIdentificacion,NumeroIdentificacion=@NumeroIdentificacion,
            DigitoVerificacion=@DigitoVerificacion,RazonSocial=@RazonSocial,EsCliente=1,Activo=1,
            NombreComercial=@NombreComercial,CodigoResponsabilidadFiscal=@CodigoResponsabilidadFiscal,
            RegimenFiscalCodigo=@RegimenFiscalCodigo,RegimenFiscalNombre=@RegimenFiscalNombre,
            Direccion=@Direccion,CiudadCodigo=@CiudadCodigo,Ciudad=@Ciudad,DepartamentoCodigo=@DepartamentoCodigo,
            Departamento=@Departamento,CodigoPostal=@CodigoPostal,PaisCodigo=@PaisCodigo,Pais=@Pais,
            ContactoNombre=@ContactoNombre,Telefono=@Telefono,Correo=@Correo,SitioWeb=@SitioWeb,ActualizadoEnUtc=SYSUTCDATETIME()
        WHERE EmpresaId=@EmpresaId AND TerceroId=@Id;
    IF NOT EXISTS(SELECT 1 FROM ven.ClientePerfil WHERE EmpresaId=@EmpresaId AND TerceroId=@Id)
        INSERT ven.ClientePerfil(EmpresaId,TerceroId,TipoPersona,Nombre1,Apellido1,VendedorZeus,TipoClienteZeus)
        VALUES(@EmpresaId,@Id,@TipoPersona,@Nombre1,@Apellido1,@VendedorZeus,@TipoClienteZeus);
    ELSE
        UPDATE ven.ClientePerfil SET TipoPersona=@TipoPersona,Nombre1=@Nombre1,Apellido1=@Apellido1,
            VendedorZeus=@VendedorZeus,TipoClienteZeus=@TipoClienteZeus,
            ZeusEstado=CASE WHEN ZeusEstado='CLIENTE' THEN 'CLIENTE' ELSE 'PENDIENTE' END,
            ZeusActualizadoEnUtc=SYSUTCDATETIME()
        WHERE EmpresaId=@EmpresaId AND TerceroId=@Id;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'CLIENTE_CREADO' ELSE 'CLIENTE_ACTUALIZADO' END,'ter.Tercero',CONVERT(nvarchar(100),@Id),'MAESTROS');
    COMMIT; SELECT @Id TerceroId,@Creado Creado;
END;
GO
