SET NOCOUNT ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@OtraEmpresaId bigint,@SolicitanteId bigint,@AprobadorId bigint,@RolSolicitaId bigint,@RolApruebaId bigint,
        @PermisoCrearId bigint,@PermisoAprobarId bigint,@AprobacionId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('PER-',@Suffix),CONCAT('3',RIGHT(@Suffix,9)),N'Empresa QA permisos'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('OTR-',@Suffix),CONCAT('4',RIGHT(@Suffix,9)),N'Otra empresa QA'); SET @OtraEmpresaId=SCOPE_IDENTITY();
INSERT seg.Usuario(Correo,NombreCompleto) VALUES(CONCAT('sol-',@Suffix,'@qa.local'),N'Usuario solicitante'); SET @SolicitanteId=SCOPE_IDENTITY();
INSERT seg.Usuario(Correo,NombreCompleto) VALUES(CONCAT('apr-',@Suffix,'@qa.local'),N'Usuario aprobador'); SET @AprobadorId=SCOPE_IDENTITY();
INSERT seg.Rol(Codigo,Nombre) VALUES(CONCAT('SOL-',@Suffix),N'Rol solicitante'); SET @RolSolicitaId=SCOPE_IDENTITY();
INSERT seg.Rol(Codigo,Nombre) VALUES(CONCAT('APR-',@Suffix),N'Rol aprobador'); SET @RolApruebaId=SCOPE_IDENTITY();
SELECT @PermisoCrearId=PermisoId FROM seg.Permiso WHERE Codigo='COMPRAS.DOCUMENTO.CREAR';
SELECT @PermisoAprobarId=PermisoId FROM seg.Permiso WHERE Codigo='INVENTARIO.PERIODO.REABRIR';
INSERT seg.RolPermiso(RolId,PermisoId) VALUES(@RolSolicitaId,@PermisoCrearId),(@RolApruebaId,@PermisoAprobarId);
INSERT seg.UsuarioEmpresaRol(EmpresaId,UsuarioId,RolId) VALUES(@EmpresaId,@SolicitanteId,@RolSolicitaId),(@EmpresaId,@AprobadorId,@RolApruebaId);

IF seg.fn_TienePermiso(@EmpresaId,@SolicitanteId,'COMPRAS.DOCUMENTO.CREAR')<>1
    THROW 51970,'El permiso del rol no fue reconocido.',1;
IF seg.fn_TienePermiso(@EmpresaId,@SolicitanteId,'INVENTARIO.PERIODO.REABRIR')<>0
    THROW 51971,'El usuario obtuvo un permiso no asignado.',1;
IF seg.fn_TienePermiso(@OtraEmpresaId,@SolicitanteId,'COMPRAS.DOCUMENTO.CREAR')<>0
    THROW 51972,'El permiso se filtro incorrectamente hacia otra empresa.',1;

INSERT seg.UsuarioEmpresaPermiso(EmpresaId,UsuarioId,PermisoId,Permitido,Motivo)
VALUES(@EmpresaId,@SolicitanteId,@PermisoCrearId,0,N'Restriccion individual de prueba');
IF seg.fn_TienePermiso(@EmpresaId,@SolicitanteId,'COMPRAS.DOCUMENTO.CREAR')<>0
    THROW 51973,'La denegacion individual no prevalecio sobre el rol.',1;
UPDATE seg.UsuarioEmpresaPermiso SET Permitido=1,Motivo=N'Autorizacion individual de prueba' WHERE EmpresaId=@EmpresaId AND UsuarioId=@SolicitanteId AND PermisoId=@PermisoCrearId;
IF seg.fn_TienePermiso(@EmpresaId,@SolicitanteId,'COMPRAS.DOCUMENTO.CREAR')<>1
    THROW 51974,'La autorizacion individual no fue reconocida.',1;

DECLARE @Solicitud TABLE(AprobacionOperacionId bigint,Estado varchar(15));
INSERT @Solicitud EXEC seg.usp_SolicitarAprobacionOperacion @EmpresaId=@EmpresaId,@Entidad=N'core.PeriodoInventario',@EntidadId=N'100',
    @TipoOperacion='REAPERTURA',@PermisoRequerido='INVENTARIO.PERIODO.REABRIR',@Justificacion=N'Ajuste contable aprobado por auditoria',@UsuarioId=@SolicitanteId;
SELECT @AprobacionId=AprobacionOperacionId FROM @Solicitud;
EXEC seg.usp_ResolverAprobacionOperacion @EmpresaId=@EmpresaId,@AprobacionOperacionId=@AprobacionId,@Aprobar=1,@Comentario=N'Aprobado por responsable independiente',@UsuarioId=@AprobadorId;
IF NOT EXISTS(SELECT 1 FROM seg.AprobacionOperacion WHERE EmpresaId=@EmpresaId AND AprobacionOperacionId=@AprobacionId AND Estado='APROBADA' AND SolicitadoPorUsuarioId=@SolicitanteId AND AprobadoPorUsuarioId=@AprobadorId)
    THROW 51975,'La aprobacion segregada no quedo registrada.',1;
IF (SELECT COUNT(*) FROM audit.Evento WHERE EmpresaId=@EmpresaId AND Entidad='seg.AprobacionOperacion')<>2
    THROW 51976,'La solicitud y resolucion no quedaron auditadas.',1;
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_AprobacionOperacion_Segregacion')
    THROW 51977,'No existe la restriccion solicitante-aprobador.',1;

ROLLBACK;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA permisos correcto: acciones por rol y empresa, excepciones y aprobacion segregada.';
