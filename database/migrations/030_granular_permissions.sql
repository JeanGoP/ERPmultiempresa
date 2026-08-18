SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='030_granular_permissions')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    CREATE TABLE seg.Permiso
    (
        PermisoId bigint IDENTITY(1,1) NOT NULL,
        Codigo varchar(100) NOT NULL,
        Modulo varchar(40) NOT NULL,
        Accion varchar(40) NOT NULL,
        Nombre nvarchar(150) NOT NULL,
        EsCritico bit NOT NULL CONSTRAINT DF_Permiso_Critico DEFAULT 0,
        Activo bit NOT NULL CONSTRAINT DF_Permiso_Activo DEFAULT 1,
        CONSTRAINT PK_Permiso PRIMARY KEY CLUSTERED(PermisoId),
        CONSTRAINT UQ_Permiso_Codigo UNIQUE(Codigo)
    );

    CREATE TABLE seg.RolPermiso
    (
        RolId bigint NOT NULL,
        PermisoId bigint NOT NULL,
        CONSTRAINT PK_RolPermiso PRIMARY KEY CLUSTERED(RolId,PermisoId),
        CONSTRAINT FK_RolPermiso_Rol FOREIGN KEY(RolId) REFERENCES seg.Rol(RolId),
        CONSTRAINT FK_RolPermiso_Permiso FOREIGN KEY(PermisoId) REFERENCES seg.Permiso(PermisoId)
    );

    CREATE TABLE seg.UsuarioEmpresaPermiso
    (
        EmpresaId bigint NOT NULL,
        UsuarioId bigint NOT NULL,
        PermisoId bigint NOT NULL,
        Permitido bit NOT NULL,
        Motivo nvarchar(300) NOT NULL,
        AsignadoPorUsuarioId bigint NULL,
        AsignadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_UsuarioEmpresaPermiso_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_UsuarioEmpresaPermiso PRIMARY KEY CLUSTERED(EmpresaId,UsuarioId,PermisoId),
        CONSTRAINT FK_UsuarioEmpresaPermiso_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_UsuarioEmpresaPermiso_Usuario FOREIGN KEY(UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT FK_UsuarioEmpresaPermiso_Permiso FOREIGN KEY(PermisoId) REFERENCES seg.Permiso(PermisoId),
        CONSTRAINT FK_UsuarioEmpresaPermiso_Asignador FOREIGN KEY(AsignadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId)
    );

    CREATE TABLE seg.AprobacionOperacion
    (
        AprobacionOperacionId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        Entidad nvarchar(150) NOT NULL,
        EntidadId nvarchar(100) NOT NULL,
        TipoOperacion varchar(50) NOT NULL,
        PermisoRequerido varchar(100) NOT NULL,
        SolicitadoPorUsuarioId bigint NOT NULL,
        SolicitadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_AprobacionOperacion_Solicitud DEFAULT SYSUTCDATETIME(),
        Estado varchar(15) NOT NULL CONSTRAINT DF_AprobacionOperacion_Estado DEFAULT 'SOLICITADA',
        AprobadoPorUsuarioId bigint NULL,
        ResueltoEnUtc datetime2(7) NULL,
        Justificacion nvarchar(500) NOT NULL,
        ComentarioResolucion nvarchar(500) NULL,
        CONSTRAINT PK_AprobacionOperacion PRIMARY KEY CLUSTERED(AprobacionOperacionId),
        CONSTRAINT UQ_AprobacionOperacion_EmpresaId UNIQUE(EmpresaId,AprobacionOperacionId),
        CONSTRAINT FK_AprobacionOperacion_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT FK_AprobacionOperacion_Solicitante FOREIGN KEY(SolicitadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT FK_AprobacionOperacion_Aprobador FOREIGN KEY(AprobadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_AprobacionOperacion_Estado CHECK(Estado IN('SOLICITADA','APROBADA','RECHAZADA','CANCELADA')),
        CONSTRAINT CK_AprobacionOperacion_Segregacion CHECK(AprobadoPorUsuarioId IS NULL OR AprobadoPorUsuarioId<>SolicitadoPorUsuarioId)
    );
    CREATE UNIQUE INDEX UX_AprobacionOperacion_Pendiente ON seg.AprobacionOperacion(EmpresaId,Entidad,EntidadId,TipoOperacion) WHERE Estado='SOLICITADA';

    INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico) VALUES
    ('COMPRAS.DOCUMENTO.CREAR','COMPRAS','CREAR',N'Crear documentos de proveedor',0),
    ('COMPRAS.RECEPCION.CONTABILIZAR','COMPRAS','CONTABILIZAR',N'Contabilizar entradas de mercancia',1),
    ('COMPRAS.SERVICIO.CAUSAR','COMPRAS','CONTABILIZAR',N'Causar servicios de proveedor',1),
    ('COMPRAS.DEVOLUCION.CONTABILIZAR','COMPRAS','DEVOLVER',N'Contabilizar devoluciones a proveedor',1),
    ('VENTAS.DEVOLUCION.CONTABILIZAR','VENTAS','DEVOLVER',N'Contabilizar devoluciones de venta',1),
    ('INVENTARIO.TRASLADO.DESPACHAR','INVENTARIO','DESPACHAR',N'Despachar traslados',0),
    ('INVENTARIO.TRASLADO.RECIBIR','INVENTARIO','RECIBIR',N'Recibir traslados',0),
    ('INVENTARIO.CONTEO.INICIAR','INVENTARIO','INICIAR_CONTEO',N'Iniciar conteos fisicos',0),
    ('INVENTARIO.CONTEO.CAPTURAR','INVENTARIO','CAPTURAR_CONTEO',N'Capturar conteos fisicos',0),
    ('INVENTARIO.CONTEO.APROBAR','INVENTARIO','APROBAR_CONTEO',N'Aprobar diferencias de conteo',1),
    ('INVENTARIO.CONTEO.APLICAR','INVENTARIO','APLICAR_CONTEO',N'Aplicar ajustes de conteo',1),
    ('INVENTARIO.NEGATIVO.AUTORIZAR','INVENTARIO','AUTORIZAR_NEGATIVO',N'Autorizar salidas excepcionales',1),
    ('INVENTARIO.AJUSTE.REVERSAR','INVENTARIO','REVERSAR',N'Reversar movimientos de inventario',1),
    ('COSTOS.DISTRIBUCION.APROBAR','COSTOS','APROBAR',N'Aprobar distribuciones de costos',1),
    ('COSTOS.DISTRIBUCION.APLICAR','COSTOS','APLICAR',N'Aplicar distribuciones de costos',1),
    ('COSTOS.DETERIORO.REGISTRAR','COSTOS','DETERIORAR',N'Registrar deterioros y reversiones',1),
    ('INVENTARIO.PERIODO.CERRAR','INVENTARIO','CERRAR_PERIODO',N'Cerrar periodos de inventario',1),
    ('INVENTARIO.PERIODO.REABRIR','INVENTARIO','REABRIR_PERIODO',N'Reabrir periodos de inventario',1),
    ('SEGURIDAD.PERMISOS.ADMINISTRAR','SEGURIDAD','ADMINISTRAR',N'Administrar roles y permisos',1);

    DECLARE @AdminRolId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='ADMIN');
    IF @AdminRolId IS NULL
    BEGIN INSERT seg.Rol(Codigo,Nombre) VALUES('ADMIN',N'Administrador'); SET @AdminRolId=SCOPE_IDENTITY(); END;
    INSERT seg.RolPermiso(RolId,PermisoId) SELECT @AdminRolId,PermisoId FROM seg.Permiso;

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON seg.UsuarioEmpresaPermiso;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON seg.UsuarioEmpresaPermiso AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON seg.UsuarioEmpresaPermiso AFTER UPDATE;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON seg.AprobacionOperacion;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON seg.AprobacionOperacion AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON seg.AprobacionOperacion AFTER UPDATE;');

    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('030_granular_permissions',N'Permisos por accion y empresa, excepciones y segregacion solicitante-aprobador');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER FUNCTION seg.fn_TienePermiso(@EmpresaId bigint,@UsuarioId bigint,@CodigoPermiso varchar(100))
RETURNS bit
AS
BEGIN
    DECLARE @Resultado bit=0,@PermisoId bigint,@Excepcion bit;
    SELECT @PermisoId=PermisoId FROM seg.Permiso WHERE Codigo=@CodigoPermiso AND Activo=1;
    IF @PermisoId IS NULL RETURN 0;
    IF NOT EXISTS(SELECT 1 FROM seg.Usuario u WHERE u.UsuarioId=@UsuarioId AND u.Activo=1) RETURN 0;
    IF NOT EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND Activo=1) RETURN 0;
    SELECT @Excepcion=Permitido FROM seg.UsuarioEmpresaPermiso WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND PermisoId=@PermisoId;
    IF @Excepcion IS NOT NULL RETURN @Excepcion;
    IF EXISTS
    (
        SELECT 1 FROM seg.UsuarioEmpresaRol ur
        JOIN seg.RolPermiso rp ON rp.RolId=ur.RolId AND rp.PermisoId=@PermisoId
        WHERE ur.EmpresaId=@EmpresaId AND ur.UsuarioId=@UsuarioId AND ur.Activo=1
    ) SET @Resultado=1;
    RETURN @Resultado;
END;
GO

CREATE OR ALTER PROCEDURE seg.usp_ValidarPermiso
    @EmpresaId bigint,@UsuarioId bigint,@CodigoPermiso varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF seg.fn_TienePermiso(@EmpresaId,@UsuarioId,@CodigoPermiso)=0
        THROW 51960,'El usuario no tiene el permiso requerido en la empresa.',1;
END;
GO

CREATE OR ALTER PROCEDURE seg.usp_SolicitarAprobacionOperacion
    @EmpresaId bigint,@Entidad nvarchar(150),@EntidadId nvarchar(100),@TipoOperacion varchar(50),
    @PermisoRequerido varchar(100),@Justificacion nvarchar(500),@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NOT EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND Activo=1)
        THROW 51961,'El solicitante no tiene acceso activo a la empresa.',1;
    IF NOT EXISTS(SELECT 1 FROM seg.Permiso WHERE Codigo=@PermisoRequerido AND Activo=1)
        THROW 51962,'El permiso requerido no existe.',1;
    IF LEN(LTRIM(RTRIM(COALESCE(@Justificacion,N''))))<10 THROW 51963,'La solicitud requiere una justificacion suficiente.',1;
    BEGIN TRANSACTION;
    DECLARE @Id bigint;
    SELECT @Id=AprobacionOperacionId FROM seg.AprobacionOperacion WITH(UPDLOCK,HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND Entidad=@Entidad AND EntidadId=@EntidadId AND TipoOperacion=@TipoOperacion AND Estado='SOLICITADA';
    IF @Id IS NULL
    BEGIN
        INSERT seg.AprobacionOperacion(EmpresaId,Entidad,EntidadId,TipoOperacion,PermisoRequerido,SolicitadoPorUsuarioId,Justificacion)
        VALUES(@EmpresaId,@Entidad,@EntidadId,@TipoOperacion,@PermisoRequerido,@UsuarioId,@Justificacion);
        SET @Id=SCOPE_IDENTITY();
        INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
        VALUES(@EmpresaId,@UsuarioId,'APROBACION_SOLICITADA','seg.AprobacionOperacion',CONVERT(nvarchar(100),@Id),CONCAT(N'{"entidad":"',STRING_ESCAPE(@Entidad,'json'),N'","tipo":"',STRING_ESCAPE(@TipoOperacion,'json'),N'"}'),'SEGURIDAD');
    END;
    COMMIT;
    SELECT @Id AprobacionOperacionId,CAST('SOLICITADA' AS varchar(15)) Estado;
END;
GO

CREATE OR ALTER PROCEDURE seg.usp_ResolverAprobacionOperacion
    @EmpresaId bigint,@AprobacionOperacionId bigint,@Aprobar bit,@Comentario nvarchar(500),@UsuarioId bigint
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(15),@Solicitante bigint,@Permiso varchar(100),@Entidad nvarchar(150),@EntidadId nvarchar(100);
    SELECT @Estado=Estado,@Solicitante=SolicitadoPorUsuarioId,@Permiso=PermisoRequerido,@Entidad=Entidad,@EntidadId=EntidadId
    FROM seg.AprobacionOperacion WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND AprobacionOperacionId=@AprobacionOperacionId;
    IF @Estado IS NULL THROW 51964,'La solicitud de aprobacion no existe.',1;
    IF @Estado<>'SOLICITADA' THROW 51965,'La solicitud ya fue resuelta.',1;
    IF @Solicitante=@UsuarioId THROW 51966,'El solicitante no puede aprobar ni rechazar su propia operacion.',1;
    IF seg.fn_TienePermiso(@EmpresaId,@UsuarioId,@Permiso)=0 THROW 51967,'El usuario no tiene el permiso exigido para resolver la solicitud.',1;
    UPDATE seg.AprobacionOperacion SET Estado=CASE WHEN @Aprobar=1 THEN 'APROBADA' ELSE 'RECHAZADA' END,
        AprobadoPorUsuarioId=@UsuarioId,ResueltoEnUtc=SYSUTCDATETIME(),ComentarioResolucion=@Comentario
    WHERE EmpresaId=@EmpresaId AND AprobacionOperacionId=@AprobacionOperacionId;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Aprobar=1 THEN 'APROBACION_OTORGADA' ELSE 'APROBACION_RECHAZADA' END,
        'seg.AprobacionOperacion',CONVERT(nvarchar(100),@AprobacionOperacionId),CONCAT(N'{"entidad":"',STRING_ESCAPE(@Entidad,'json'),N'","entidadId":"',STRING_ESCAPE(@EntidadId,'json'),N'"}'),'SEGURIDAD');
    COMMIT;
    SELECT @AprobacionOperacionId AprobacionOperacionId,CAST(CASE WHEN @Aprobar=1 THEN 'APROBADA' ELSE 'RECHAZADA' END AS varchar(15)) Estado;
END;
GO
