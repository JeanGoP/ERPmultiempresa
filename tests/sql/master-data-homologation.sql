SET NOCOUNT ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UsuarioId bigint,@ProveedorId bigint,@UnidadId bigint,@UnidadCajaId bigint,@ArticuloId bigint,@BodegaId bigint,@HomologacionId bigint;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('MST-',@Suffix),CONCAT('7',RIGHT(@Suffix,9)),N'Empresa QA Maestros'); SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
INSERT seg.Usuario(Correo,NombreCompleto) VALUES(CONCAT('master-',@Suffix,'@qa.local'),N'Administrador de maestros'); SET @UsuarioId=SCOPE_IDENTITY();

DECLARE @Unidad TABLE(Id bigint,Creado bit);
INSERT @Unidad EXEC inv.usp_GuardarUnidadMedida @EmpresaId=@EmpresaId,@Codigo='UND',@Nombre=N'Unidad',@Simbolo='und',@UsuarioId=@UsuarioId;
SELECT @UnidadId=Id FROM @Unidad;
DELETE FROM @Unidad;
INSERT @Unidad EXEC inv.usp_GuardarUnidadMedida @EmpresaId=@EmpresaId,@Codigo='CJ12',@Nombre=N'Caja por 12',@Simbolo='caja',@UsuarioId=@UsuarioId;
SELECT @UnidadCajaId=Id FROM @Unidad;

DECLARE @Proveedor TABLE(Id bigint,Creado bit);
INSERT @Proveedor EXEC ter.usp_GuardarProveedor @EmpresaId=@EmpresaId,@TipoIdentificacion='NIT',@NumeroIdentificacion='890301886',@DigitoVerificacion='5',@RazonSocial=N'Proveedor QA',@UsuarioId=@UsuarioId;
SELECT @ProveedorId=Id FROM @Proveedor;

DECLARE @Articulo TABLE(Id bigint,Creado bit);
INSERT @Articulo EXEC inv.usp_GuardarArticulo @EmpresaId=@EmpresaId,@Codigo='MOTO-XR',@Descripcion=N'Motocicleta XR',@Tipo='INVENTARIO',@UnidadBaseId=@UnidadId,@ManejaInventario=1,@ManejaSerial=1,@UsuarioId=@UsuarioId;
SELECT @ArticuloId=Id FROM @Articulo;
EXEC inv.usp_GuardarArticuloUnidad @EmpresaId=@EmpresaId,@ArticuloId=@ArticuloId,@UnidadMedidaId=@UnidadCajaId,@FactorAUnidadBase=12,@EsUnidadCompra=1,@EsUnidadVenta=0,@UsuarioId=@UsuarioId;

DECLARE @Bodega TABLE(Id bigint,Creado bit);
INSERT @Bodega EXEC inv.usp_GuardarBodega @EmpresaId=@EmpresaId,@Codigo='PPL',@Nombre=N'Bodega principal',@UsaUbicaciones=1,@UsuarioId=@UsuarioId;
SELECT @BodegaId=Id FROM @Bodega;

DECLARE @Homologacion TABLE(Id bigint,Creado bit);
INSERT @Homologacion EXEC comp.usp_GuardarHomologacionArticulo @EmpresaId=@EmpresaId,@TerceroId=@ProveedorId,@CodigoExterno='357683',@DescripcionExterna=N'Motocicleta proveedor',@ArticuloId=@ArticuloId,@UnidadMedidaId=@UnidadId,@FactorAUnidadBase=1,@UsuarioId=@UsuarioId;
SELECT @HomologacionId=Id FROM @Homologacion;
DELETE FROM @Homologacion;
INSERT @Homologacion EXEC comp.usp_GuardarHomologacionArticulo @EmpresaId=@EmpresaId,@TerceroId=@ProveedorId,@CodigoExterno='357683',@DescripcionExterna=N'Motocicleta proveedor actualizada',@ArticuloId=@ArticuloId,@UnidadMedidaId=@UnidadId,@FactorAUnidadBase=1,@UsuarioId=@UsuarioId;

IF (SELECT COUNT(*) FROM comp.HomologacionArticuloProveedor WHERE EmpresaId=@EmpresaId AND TerceroId=@ProveedorId AND CodigoExterno='357683')<>1 THROW 52020,'La homologacion no fue idempotente.',1;
IF NOT EXISTS(SELECT 1 FROM inv.ArticuloUnidad WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND UnidadMedidaId=@UnidadId AND FactorAUnidadBase=1) THROW 52021,'La unidad base del articulo no fue configurada.',1;
IF NOT EXISTS(SELECT 1 FROM inv.ArticuloUnidad WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND UnidadMedidaId=@UnidadCajaId AND FactorAUnidadBase=12 AND EsUnidadCompra=1) THROW 52025,'La conversion de compra del articulo no fue configurada.',1;
IF NOT EXISTS(SELECT 1 FROM inv.Articulo WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND ManejaSerial=1) THROW 52022,'La configuracion de seriales no fue guardada.',1;
IF NOT EXISTS(SELECT 1 FROM inv.Bodega WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND UsaUbicaciones=1) THROW 52023,'La configuracion de ubicaciones no fue guardada.',1;
IF (SELECT COUNT(*) FROM audit.Evento WHERE EmpresaId=@EmpresaId AND AplicacionOrigen IN('MAESTROS','COMPRAS'))<6 THROW 52024,'Las operaciones maestras no quedaron auditadas.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA maestros correcto: proveedor, unidad, articulo, bodega y homologacion auditada e idempotente.';
