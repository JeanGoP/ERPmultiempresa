SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='040_warehouse_receiving_checks')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;

    IF NOT EXISTS(SELECT 1 FROM seg.Permiso WHERE Codigo='COMPRAS.RECEPCION.REVISAR')
        INSERT seg.Permiso(Codigo,Modulo,Accion,Nombre,EsCritico)
        VALUES('COMPRAS.RECEPCION.REVISAR','COMPRAS','REVISAR',N'Revisar físicamente entradas de mercancía',0);

    DECLARE @AuxRolId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='AUXILIAR_BODEGA');
    IF @AuxRolId IS NULL
    BEGIN
        INSERT seg.Rol(Codigo,Nombre) VALUES('AUXILIAR_BODEGA',N'Auxiliar de bodega');
        SET @AuxRolId=SCOPE_IDENTITY();
    END;

    INSERT seg.RolPermiso(RolId,PermisoId)
    SELECT @AuxRolId,p.PermisoId
    FROM seg.Permiso p
    WHERE p.Codigo IN('COMPRAS.RECEPCION.REVISAR','COMPRAS.RECEPCION.CONTABILIZAR')
      AND NOT EXISTS(SELECT 1 FROM seg.RolPermiso rp WHERE rp.RolId=@AuxRolId AND rp.PermisoId=p.PermisoId);

    DECLARE @AdminRolId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='ADMIN');
    IF @AdminRolId IS NOT NULL
        INSERT seg.RolPermiso(RolId,PermisoId)
        SELECT @AdminRolId,p.PermisoId
        FROM seg.Permiso p
        WHERE p.Codigo='COMPRAS.RECEPCION.REVISAR'
          AND NOT EXISTS(SELECT 1 FROM seg.RolPermiso rp WHERE rp.RolId=@AdminRolId AND rp.PermisoId=p.PermisoId);

    CREATE TABLE inv.RecepcionMercanciaRevisionUnidad
    (
        RecepcionMercanciaRevisionUnidadId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        RecepcionMercanciaUnidadId bigint NOT NULL,
        EstadoFisico varchar(20) NOT NULL,
        Observacion nvarchar(500) NULL,
        RevisadoPorUsuarioId bigint NOT NULL,
        RevisadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_RecepcionRevision_Fecha DEFAULT SYSUTCDATETIME(),
        ActualizadoEnUtc datetime2(7) NULL,
        CONSTRAINT PK_RecepcionMercanciaRevisionUnidad PRIMARY KEY CLUSTERED(RecepcionMercanciaRevisionUnidadId),
        CONSTRAINT UQ_RecepcionMercanciaRevisionUnidad UNIQUE(EmpresaId,RecepcionMercanciaUnidadId),
        CONSTRAINT FK_RecepcionRevision_Unidad FOREIGN KEY(EmpresaId,RecepcionMercanciaUnidadId) REFERENCES inv.RecepcionMercanciaUnidad(EmpresaId,RecepcionMercanciaUnidadId),
        CONSTRAINT FK_RecepcionRevision_Usuario FOREIGN KEY(RevisadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_RecepcionRevision_Estado CHECK(EstadoFisico IN('RECIBIDA_CONFORME','RECIBIDA_NOVEDAD','NO_RECIBIDA'))
    );

    CREATE INDEX IX_RecepcionRevision_UsuarioFecha
        ON inv.RecepcionMercanciaRevisionUnidad(EmpresaId,RevisadoPorUsuarioId,RevisadoEnUtc DESC)
        INCLUDE(EstadoFisico,RecepcionMercanciaUnidadId);

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.RecepcionMercanciaRevisionUnidad;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.RecepcionMercanciaRevisionUnidad AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.RecepcionMercanciaRevisionUnidad AFTER UPDATE;');

    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('040_warehouse_receiving_checks',N'Revisión física de unidades recibidas y rol auxiliar de bodega');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO
