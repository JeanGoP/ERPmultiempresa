-- SQLCMD: ejecutar primero con -v Aplicar=NO. Repetir con Aplicar=SI para guardar.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Aplicar varchar(2) = '$(Aplicar)';
DECLARE @EmpresaId bigint = 3;
DECLARE @Lote uniqueidentifier = '265b341b-f37f-4845-8d99-043f36b6440b';
IF @Aplicar NOT IN ('NO', 'SI') OR DB_NAME() <> N'ERPMontelibano'
    THROW 52480, N'Indica Aplicar=NO o SI y usa la base ERPMontelibano.', 1;

EXEC sys.sp_set_session_context @key=N'EmpresaId', @value=@EmpresaId;
IF NOT EXISTS (SELECT 1 FROM core.Empresa WHERE EmpresaId=@EmpresaId AND Codigo='01' AND RazonSocial=N'MOTOCENTRO SA')
    THROW 52481, N'No se encontró el catálogo esperado de MOTOCENTRO.', 1;

DECLARE @Tecnologia TABLE (Codigo nvarchar(50) NOT NULL PRIMARY KEY);
-- Televisores, parlantes y sus soportes. Códigos revisados en el catálogo activo.
INSERT @Tecnologia (Codigo) VALUES
    (N'7705946476911'), (N'7705946480314'), (N'7705946476980'), (N'6921732899356'),
    (N'7705946477048'), (N'7705946480079'), (N'7705946474658'), (N'7705946477994'),
    (N'7705946477390'), (N'7705946476683'), (N'7705946171083'), (N'7705946480116');

BEGIN TRANSACTION;

-- Si el catálogo cambió después de la revisión, exige revalidar las excepciones.
DECLARE @Huella varbinary(32) = HASHBYTES('SHA2_256', (
    SELECT Codigo, Descripcion FROM inv.Articulo WITH (UPDLOCK, HOLDLOCK)
    WHERE EmpresaId=@EmpresaId AND Activo=1 ORDER BY Codigo FOR JSON PATH
));
IF @Huella IS NULL OR @Huella <> 0x977082334691F63AA04FD3096395B13E171035114869AA35ED437082B62B4F7F
    THROW 52482, N'El catálogo cambió. Vuelve a revisar los artículos de tecnología.', 1;

DECLARE @Excepciones TABLE (ArticuloId bigint PRIMARY KEY, Codigo nvarchar(50), Iva decimal(9,4) NULL);
INSERT @Excepciones
SELECT a.ArticuloId, a.Codigo, a.PorcentajeIvaVenta
FROM inv.Articulo a JOIN @Tecnologia t ON t.Codigo=a.Codigo
WHERE a.EmpresaId=@EmpresaId AND a.Activo=1;
IF (SELECT COUNT(*) FROM @Excepciones) <> (SELECT COUNT(*) FROM @Tecnologia)
    THROW 52483, N'No se pudieron identificar todas las excepciones de tecnología.', 1;

DECLARE @Pendientes int = (
    SELECT COUNT(*) FROM inv.Articulo a
    WHERE a.EmpresaId=@EmpresaId AND a.Activo=1 AND (a.PorcentajeIvaVenta IS NULL OR a.PorcentajeIvaVenta<>19)
      AND NOT EXISTS (SELECT 1 FROM @Excepciones t WHERE t.ArticuloId=a.ArticuloId)
);
SELECT @@SERVERNAME AS Servidor, DB_NAME() AS BaseActual, @EmpresaId AS EmpresaId,
    @Pendientes AS PorActualizar, (SELECT COUNT(*) FROM @Excepciones) AS Excepciones;
IF @Aplicar='NO'
BEGIN
    SELECT Codigo, Iva FROM @Excepciones ORDER BY Codigo;
    ROLLBACK TRANSACTION;
    RETURN;
END;

IF EXISTS (SELECT 1 FROM audit.Evento WHERE EmpresaId=@EmpresaId AND CorrelationId=@Lote)
    THROW 52484, N'Este lote de IVA ya se aplicó.', 1;
IF @Pendientes<>240
    THROW 52485, N'Cambió el número de tarifas que se actualizarían. Revisa la vista previa.', 1;

DECLARE @Cambios TABLE (ArticuloId bigint PRIMARY KEY, Codigo nvarchar(50), IvaAnterior decimal(9,4) NULL);
UPDATE a SET PorcentajeIvaVenta=19
OUTPUT inserted.ArticuloId, inserted.Codigo, deleted.PorcentajeIvaVenta INTO @Cambios
FROM inv.Articulo a
WHERE a.EmpresaId=@EmpresaId AND a.Activo=1 AND (a.PorcentajeIvaVenta IS NULL OR a.PorcentajeIvaVenta<>19)
  AND NOT EXISTS (SELECT 1 FROM @Excepciones t WHERE t.ArticuloId=a.ArticuloId);

INSERT audit.Evento(EmpresaId, Operacion, Entidad, EntidadId, Motivo, ValoresAnteriores, ValoresPosteriores, AplicacionOrigen, CorrelationId)
SELECT @EmpresaId, 'ARTICULO_IVA_VENTA_ACTUALIZADO', 'inv.Articulo', CONVERT(nvarchar(100), c.ArticuloId),
    N'Asignar IVA de venta del 19 % al catálogo activo, excepto tecnología.',
    (SELECT c.Codigo, c.IvaAnterior AS PorcentajeIvaVenta FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
    (SELECT c.Codigo, 19 AS PorcentajeIvaVenta FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    'MAESTROS', @Lote
FROM @Cambios c;

IF (SELECT COUNT(*) FROM @Cambios)<>@Pendientes OR EXISTS (
    SELECT a.ArticuloId, a.PorcentajeIvaVenta FROM inv.Articulo a JOIN @Excepciones t ON t.ArticuloId=a.ArticuloId
    WHERE a.EmpresaId=@EmpresaId
    EXCEPT SELECT ArticuloId, Iva FROM @Excepciones
)
    THROW 52486, N'La verificación del lote de IVA falló.', 1;

COMMIT TRANSACTION;
SELECT @Lote AS LoteAuditoria, (SELECT COUNT(*) FROM @Cambios) AS Actualizados;
