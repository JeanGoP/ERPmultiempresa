SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='033_master_data_and_item_mapping')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    CREATE TABLE comp.HomologacionArticuloProveedor
    (
        HomologacionArticuloProveedorId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        TerceroId bigint NOT NULL,
        CodigoExterno nvarchar(80) NOT NULL,
        DescripcionExterna nvarchar(300) NULL,
        ArticuloId bigint NOT NULL,
        UnidadMedidaId bigint NULL,
        FactorAUnidadBase decimal(20,10) NOT NULL CONSTRAINT DF_Homologacion_Factor DEFAULT 1,
        Activa bit NOT NULL CONSTRAINT DF_Homologacion_Activa DEFAULT 1,
        CreadoPorUsuarioId bigint NOT NULL,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_Homologacion_Creado DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_Homologacion_Actualizado DEFAULT SYSUTCDATETIME(),
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_HomologacionArticuloProveedor PRIMARY KEY CLUSTERED(HomologacionArticuloProveedorId),
        CONSTRAINT UQ_HomologacionArticuloProveedor_EmpresaId UNIQUE(EmpresaId,HomologacionArticuloProveedorId),
        CONSTRAINT UQ_HomologacionArticuloProveedor_Codigo UNIQUE(EmpresaId,TerceroId,CodigoExterno),
        CONSTRAINT FK_HomologacionArticuloProveedor_Tercero FOREIGN KEY(EmpresaId,TerceroId) REFERENCES ter.Tercero(EmpresaId,TerceroId),
        CONSTRAINT FK_HomologacionArticuloProveedor_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_HomologacionArticuloProveedor_Unidad FOREIGN KEY(EmpresaId,UnidadMedidaId) REFERENCES inv.UnidadMedida(EmpresaId,UnidadMedidaId),
        CONSTRAINT FK_HomologacionArticuloProveedor_Usuario FOREIGN KEY(CreadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_HomologacionArticuloProveedor_Codigo CHECK(LEN(LTRIM(RTRIM(CodigoExterno)))>0),
        CONSTRAINT CK_HomologacionArticuloProveedor_Factor CHECK(FactorAUnidadBase>0)
    );
    CREATE INDEX IX_HomologacionArticuloProveedor_Articulo ON comp.HomologacionArticuloProveedor(EmpresaId,ArticuloId,TerceroId) INCLUDE(CodigoExterno,Activa);

    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico)
    SELECT v.Codigo,v.Modulo,v.Accion,v.Nombre,v.EsCritico
    FROM (VALUES
        (CAST('MAESTROS.PROVEEDOR.ADMINISTRAR' AS varchar(100)),CAST('MAESTROS' AS varchar(40)),CAST('PROVEEDOR' AS varchar(40)),CAST(N'Administrar proveedores' AS nvarchar(150)),CAST(0 AS bit)),
        ('MAESTROS.ARTICULO.ADMINISTRAR','MAESTROS','ARTICULO',N'Administrar articulos y servicios',0),
        ('MAESTROS.INVENTARIO.ADMINISTRAR','MAESTROS','INVENTARIO',N'Administrar unidades, bodegas y ubicaciones',0),
        ('COMPRAS.HOMOLOGACION.ADMINISTRAR','COMPRAS','HOMOLOGAR',N'Homologar codigos de proveedores',0)
    ) v(Codigo,Modulo,Accion,Nombre,EsCritico)
    WHERE NOT EXISTS(SELECT 1 FROM seg.Permiso p WHERE p.Codigo=v.Codigo);

    DECLARE @AdminRolId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='ADMIN');
    INSERT seg.RolPermiso(RolId,PermisoId)
    SELECT @AdminRolId,p.PermisoId FROM seg.Permiso p
    WHERE p.Codigo IN('MAESTROS.PROVEEDOR.ADMINISTRAR','MAESTROS.ARTICULO.ADMINISTRAR','MAESTROS.INVENTARIO.ADMINISTRAR','COMPRAS.HOMOLOGACION.ADMINISTRAR')
      AND NOT EXISTS(SELECT 1 FROM seg.RolPermiso rp WHERE rp.RolId=@AdminRolId AND rp.PermisoId=p.PermisoId);

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.HomologacionArticuloProveedor;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.HomologacionArticuloProveedor AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON comp.HomologacionArticuloProveedor AFTER UPDATE;');

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('033_master_data_and_item_mapping',N'Maestros auditados y homologacion de codigos externos por proveedor');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER PROCEDURE ter.usp_GuardarProveedor
    @EmpresaId bigint,@TipoIdentificacion varchar(10),@NumeroIdentificacion nvarchar(30),@DigitoVerificacion char(1)=NULL,
    @RazonSocial nvarchar(200),@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@NumeroIdentificacion)),N'') IS NULL THROW 52000,'La identificacion del proveedor es obligatoria.',1;
    IF NULLIF(LTRIM(RTRIM(@RazonSocial)),N'') IS NULL THROW 52001,'La razon social del proveedor es obligatoria.',1;
    BEGIN TRANSACTION;
    DECLARE @Id bigint,@Creado bit=0;
    SELECT @Id=TerceroId FROM ter.Tercero WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TipoIdentificacion=@TipoIdentificacion AND NumeroIdentificacion=@NumeroIdentificacion;
    IF @Id IS NULL
    BEGIN
        INSERT ter.Tercero(EmpresaId,TipoIdentificacion,NumeroIdentificacion,DigitoVerificacion,RazonSocial,EsProveedor)
        VALUES(@EmpresaId,@TipoIdentificacion,@NumeroIdentificacion,@DigitoVerificacion,@RazonSocial,1);
        SET @Id=SCOPE_IDENTITY(); SET @Creado=1;
    END
    ELSE UPDATE ter.Tercero SET DigitoVerificacion=@DigitoVerificacion,RazonSocial=@RazonSocial,EsProveedor=1,Activo=1 WHERE EmpresaId=@EmpresaId AND TerceroId=@Id;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'PROVEEDOR_CREADO' ELSE 'PROVEEDOR_ACTUALIZADO' END,'ter.Tercero',CONVERT(nvarchar(100),@Id),CONCAT(N'{"identificacion":"',STRING_ESCAPE(@NumeroIdentificacion,'json'),N'","razonSocial":"',STRING_ESCAPE(@RazonSocial,'json'),N'"}'),'MAESTROS');
    COMMIT; SELECT @Id TerceroId,@Creado Creado;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_GuardarUnidadMedida
    @EmpresaId bigint,@Codigo nvarchar(20),@Nombre nvarchar(80),@Simbolo nvarchar(15),@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@Codigo)),N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Nombre)),N'') IS NULL THROW 52002,'Codigo y nombre de unidad son obligatorios.',1;
    BEGIN TRANSACTION; DECLARE @Id bigint,@Creado bit=0;
    SELECT @Id=UnidadMedidaId FROM inv.UnidadMedida WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Codigo=@Codigo;
    IF @Id IS NULL BEGIN INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,@Codigo,@Nombre,@Simbolo); SET @Id=SCOPE_IDENTITY(); SET @Creado=1; END
    ELSE UPDATE inv.UnidadMedida SET Nombre=@Nombre,Simbolo=@Simbolo,Activa=1 WHERE EmpresaId=@EmpresaId AND UnidadMedidaId=@Id;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'UNIDAD_CREADA' ELSE 'UNIDAD_ACTUALIZADA' END,'inv.UnidadMedida',CONVERT(nvarchar(100),@Id),'MAESTROS');
    COMMIT; SELECT @Id UnidadMedidaId,@Creado Creado;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_GuardarArticulo
    @EmpresaId bigint,@Codigo nvarchar(50),@Descripcion nvarchar(300),@Tipo varchar(20),@UnidadBaseId bigint,
    @ManejaInventario bit,@ManejaLote bit=0,@ManejaSerial bit=0,@RequiereVencimiento bit=0,@PesoBaseKg decimal(20,8)=NULL,@VolumenBaseM3 decimal(20,10)=NULL,@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Tipo NOT IN('INVENTARIO','SERVICIO','ACTIVO_FIJO','CONCEPTO') THROW 52003,'El tipo de articulo no es valido.',1;
    IF @Tipo='SERVICIO' AND @ManejaInventario=1 THROW 52004,'Un servicio no puede manejar inventario.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.UnidadMedida WHERE EmpresaId=@EmpresaId AND UnidadMedidaId=@UnidadBaseId AND Activa=1) THROW 52005,'La unidad base no existe o esta inactiva.',1;
    BEGIN TRANSACTION; DECLARE @Id bigint,@Creado bit=0;
    SELECT @Id=ArticuloId FROM inv.Articulo WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Codigo=@Codigo;
    IF @Id IS NULL
    BEGIN
        INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId,ManejaLote,ManejaSerial,RequiereVencimiento,PesoBaseKg,VolumenBaseM3)
        VALUES(@EmpresaId,@Codigo,@Descripcion,@Tipo,@ManejaInventario,@UnidadBaseId,@ManejaLote,@ManejaSerial,@RequiereVencimiento,@PesoBaseKg,@VolumenBaseM3);
        SET @Id=SCOPE_IDENTITY(); SET @Creado=1;
    END
    ELSE UPDATE inv.Articulo SET Descripcion=@Descripcion,Tipo=@Tipo,ManejaInventario=@ManejaInventario,UnidadBaseId=@UnidadBaseId,ManejaLote=@ManejaLote,ManejaSerial=@ManejaSerial,RequiereVencimiento=@RequiereVencimiento,PesoBaseKg=@PesoBaseKg,VolumenBaseM3=@VolumenBaseM3,Activo=1 WHERE EmpresaId=@EmpresaId AND ArticuloId=@Id;
    IF NOT EXISTS(SELECT 1 FROM inv.ArticuloUnidad WHERE EmpresaId=@EmpresaId AND ArticuloId=@Id AND UnidadMedidaId=@UnidadBaseId)
        INSERT inv.ArticuloUnidad(EmpresaId,ArticuloId,UnidadMedidaId,FactorAUnidadBase,EsUnidadCompra,EsUnidadVenta) VALUES(@EmpresaId,@Id,@UnidadBaseId,1,1,1);
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'ARTICULO_CREADO' ELSE 'ARTICULO_ACTUALIZADO' END,'inv.Articulo',CONVERT(nvarchar(100),@Id),'MAESTROS');
    COMMIT; SELECT @Id ArticuloId,@Creado Creado;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_GuardarBodega
    @EmpresaId bigint,@Codigo nvarchar(30),@Nombre nvarchar(120),@UsaUbicaciones bit=0,@EsTransito bit=0,@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION; DECLARE @Id bigint,@Creado bit=0;
    SELECT @Id=BodegaId FROM inv.Bodega WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Codigo=@Codigo;
    IF @Id IS NULL BEGIN INSERT inv.Bodega(EmpresaId,Codigo,Nombre,UsaUbicaciones,EsTransito) VALUES(@EmpresaId,@Codigo,@Nombre,@UsaUbicaciones,@EsTransito); SET @Id=SCOPE_IDENTITY(); SET @Creado=1; END
    ELSE UPDATE inv.Bodega SET Nombre=@Nombre,UsaUbicaciones=@UsaUbicaciones,EsTransito=@EsTransito,Activa=1 WHERE EmpresaId=@EmpresaId AND BodegaId=@Id;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'BODEGA_CREADA' ELSE 'BODEGA_ACTUALIZADA' END,'inv.Bodega',CONVERT(nvarchar(100),@Id),'MAESTROS');
    COMMIT; SELECT @Id BodegaId,@Creado Creado;
END;
GO

CREATE OR ALTER PROCEDURE comp.usp_GuardarHomologacionArticulo
    @EmpresaId bigint,@TerceroId bigint,@CodigoExterno nvarchar(80),@DescripcionExterna nvarchar(300)=NULL,
    @ArticuloId bigint,@UnidadMedidaId bigint=NULL,@FactorAUnidadBase decimal(20,10)=1,@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NOT EXISTS(SELECT 1 FROM ter.Tercero WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND EsProveedor=1 AND Activo=1) THROW 52010,'El proveedor no existe o esta inactivo.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.Articulo WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND Activo=1) THROW 52011,'El articulo interno no existe o esta inactivo.',1;
    IF @UnidadMedidaId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM inv.ArticuloUnidad WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND UnidadMedidaId=@UnidadMedidaId) THROW 52012,'La unidad no esta configurada para el articulo.',1;
    BEGIN TRANSACTION; DECLARE @Id bigint,@Creado bit=0;
    SELECT @Id=HomologacionArticuloProveedorId FROM comp.HomologacionArticuloProveedor WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND TerceroId=@TerceroId AND CodigoExterno=@CodigoExterno;
    IF @Id IS NULL
    BEGIN INSERT comp.HomologacionArticuloProveedor(EmpresaId,TerceroId,CodigoExterno,DescripcionExterna,ArticuloId,UnidadMedidaId,FactorAUnidadBase,CreadoPorUsuarioId) VALUES(@EmpresaId,@TerceroId,@CodigoExterno,@DescripcionExterna,@ArticuloId,@UnidadMedidaId,@FactorAUnidadBase,@UsuarioId); SET @Id=SCOPE_IDENTITY(); SET @Creado=1; END
    ELSE UPDATE comp.HomologacionArticuloProveedor SET DescripcionExterna=@DescripcionExterna,ArticuloId=@ArticuloId,UnidadMedidaId=@UnidadMedidaId,FactorAUnidadBase=@FactorAUnidadBase,Activa=1,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND HomologacionArticuloProveedorId=@Id;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'HOMOLOGACION_CREADA' ELSE 'HOMOLOGACION_ACTUALIZADA' END,'comp.HomologacionArticuloProveedor',CONVERT(nvarchar(100),@Id),CONCAT(N'{"codigoExterno":"',STRING_ESCAPE(@CodigoExterno,'json'),N'","articuloId":',@ArticuloId,N'}'),'COMPRAS');
    COMMIT; SELECT @Id HomologacionArticuloProveedorId,@Creado Creado;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_GuardarArticuloUnidad
    @EmpresaId bigint,@ArticuloId bigint,@UnidadMedidaId bigint,@FactorAUnidadBase decimal(20,10),@EsUnidadCompra bit,@EsUnidadVenta bit,@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @FactorAUnidadBase<=0 THROW 52013,'El factor de conversion debe ser mayor que cero.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.Articulo WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND Activo=1) THROW 52014,'El articulo no existe o esta inactivo.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.UnidadMedida WHERE EmpresaId=@EmpresaId AND UnidadMedidaId=@UnidadMedidaId AND Activa=1) THROW 52015,'La unidad no existe o esta inactiva.',1;
    BEGIN TRANSACTION; DECLARE @Id bigint,@Creado bit=0;
    SELECT @Id=ArticuloUnidadId FROM inv.ArticuloUnidad WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND UnidadMedidaId=@UnidadMedidaId;
    IF @Id IS NULL BEGIN INSERT inv.ArticuloUnidad(EmpresaId,ArticuloId,UnidadMedidaId,FactorAUnidadBase,EsUnidadCompra,EsUnidadVenta) VALUES(@EmpresaId,@ArticuloId,@UnidadMedidaId,@FactorAUnidadBase,@EsUnidadCompra,@EsUnidadVenta); SET @Id=SCOPE_IDENTITY(); SET @Creado=1; END
    ELSE UPDATE inv.ArticuloUnidad SET FactorAUnidadBase=@FactorAUnidadBase,EsUnidadCompra=@EsUnidadCompra,EsUnidadVenta=@EsUnidadVenta WHERE EmpresaId=@EmpresaId AND ArticuloUnidadId=@Id;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'CONVERSION_UNIDAD_CREADA' ELSE 'CONVERSION_UNIDAD_ACTUALIZADA' END,'inv.ArticuloUnidad',CONVERT(nvarchar(100),@Id),CONCAT(N'{"factor":',@FactorAUnidadBase,N'}'),'MAESTROS');
    COMMIT; SELECT @Id ArticuloUnidadId,@Creado Creado;
END;
GO
