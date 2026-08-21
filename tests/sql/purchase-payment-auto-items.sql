SET NOCOUNT ON;
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;

DECLARE @Suffix varchar(12)=RIGHT(REPLACE(CONVERT(varchar(36),NEWID()),'-',''),12);
DECLARE @EmpresaId bigint,@UsuarioId bigint;
INSERT seg.Usuario(Correo,NombreCompleto) VALUES(CONCAT('auto-',@Suffix,'@qa.local'),N'Usuario artículos automáticos');
SET @UsuarioId=SCOPE_IDENTITY();
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES(CONCAT('AUT-',@Suffix),CONCAT('8',RIGHT(@Suffix,9)),N'Empresa QA Artículos XML');
SET @EmpresaId=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);

DECLARE @Lineas nvarchar(max)=N'[
 {"numeroLinea":1,"articuloId":null,"codigoExterno":"MOTO-EXT-01","descripcion":"Motocicleta negra modelo 2027","clasificacion":"INVENTARIO","cantidad":1,"unidadMedidaId":null,"unidadCodigo":"94","manejaSerial":true},
 {"numeroLinea":2,"articuloId":null,"codigoExterno":"MOTO-EXT-01","descripcion":"Motocicleta negra modelo 2027","clasificacion":"INVENTARIO","cantidad":1,"unidadMedidaId":null,"unidadCodigo":"94","manejaSerial":true},
 {"numeroLinea":3,"articuloId":null,"codigoExterno":"REP-EXT-01","descripcion":"Repuesto general","clasificacion":"INVENTARIO","cantidad":2,"unidadMedidaId":null,"unidadCodigo":"UND","manejaSerial":false},
 {"numeroLinea":4,"articuloId":null,"codigoExterno":"SERV-01","descripcion":"Servicio técnico","clasificacion":"SERVICIO_GASTO","cantidad":1,"unidadMedidaId":null,"unidadCodigo":"UND","manejaSerial":false}
]';

DECLARE @Resultado table(NumeroLinea int,ArticuloId bigint,UnidadMedidaId bigint,CodigoExterno nvarchar(80),CodigoInterno nvarchar(50),ArticuloCreado bit);
INSERT @Resultado EXEC comp.usp_AsegurarArticulosDocumentoXml
    @EmpresaId=@EmpresaId,@ProveedorIdentificacion=N'900AUTO01',@ProveedorRazonSocial=N'Proveedor automático QA',
    @UsuarioId=@UsuarioId,@CrearArticulosFaltantes=1,@LineasJson=@Lineas;

IF (SELECT COUNT(*) FROM @Resultado)<>3 THROW 51980,'Solo las líneas de inventario deben asegurar artículos.',1;
IF (SELECT COUNT(*) FROM @Resultado WHERE ArticuloCreado=1)<>2 THROW 51981,'No se creó exactamente una moto y un artículo general.',1;
IF (SELECT COUNT(DISTINCT ArticuloId) FROM @Resultado WHERE CodigoExterno='MOTO-EXT-01')<>1 THROW 51982,'El mismo código externo no reutilizó el artículo.',1;
IF NOT EXISTS(SELECT 1 FROM @Resultado WHERE CodigoExterno='MOTO-EXT-01' AND CodigoInterno='MOTO-EXT-01') THROW 51983,'La moto no conservó el código del proveedor.',1;
IF NOT EXISTS(SELECT 1 FROM @Resultado WHERE CodigoExterno='REP-EXT-01' AND CodigoInterno='REP-EXT-01') THROW 51984,'El artículo general no conservó el código del proveedor.',1;
IF (SELECT COUNT(*) FROM comp.HomologacionArticuloProveedor WHERE EmpresaId=@EmpresaId)<>2 THROW 51985,'Las homologaciones del proveedor no quedaron guardadas.',1;

DECLARE @Segundo table(NumeroLinea int,ArticuloId bigint,UnidadMedidaId bigint,CodigoExterno nvarchar(80),CodigoInterno nvarchar(50),ArticuloCreado bit);
INSERT @Segundo EXEC comp.usp_AsegurarArticulosDocumentoXml
    @EmpresaId=@EmpresaId,@ProveedorIdentificacion=N'900AUTO01',@ProveedorRazonSocial=N'Proveedor automático QA',
    @UsuarioId=@UsuarioId,@CrearArticulosFaltantes=1,@LineasJson=@Lineas;
IF EXISTS(SELECT 1 FROM @Segundo WHERE ArticuloCreado=1) THROW 51986,'Una segunda factura volvió a crear artículos ya homologados.',1;

ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
PRINT 'QA artículos XML correcto: códigos internos, homologación y reutilización idempotente.';
