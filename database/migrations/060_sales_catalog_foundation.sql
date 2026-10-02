SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='060_sales_catalog_foundation')
BEGIN
    EXEC(N'ALTER TABLE inv.Articulo ADD PorcentajeIvaVenta decimal(9,4) NULL;');
    EXEC(N'ALTER TABLE inv.Articulo ADD CONSTRAINT CK_Articulo_PorcentajeIvaVenta CHECK(PorcentajeIvaVenta BETWEEN 0 AND 100);');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('060_sales_catalog_foundation',N'IVA de venta configurable por artículo; NULL indica pendiente de clasificación');
END;
COMMIT;
GO
CREATE OR ALTER PROCEDURE inv.usp_GuardarArticulo
    @EmpresaId bigint,@Codigo nvarchar(50),@Descripcion nvarchar(300),@Tipo varchar(20),@UnidadBaseId bigint,
    @ManejaInventario bit,@ManejaLote bit=0,@ManejaSerial bit=0,@RequiereVencimiento bit=0,
    @PesoBaseKg decimal(20,8)=NULL,@VolumenBaseM3 decimal(20,10)=NULL,@UsuarioId bigint,
    @PorcentajeIvaVenta decimal(9,4)=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Tipo NOT IN('INVENTARIO','SERVICIO','ACTIVO_FIJO','CONCEPTO') THROW 52003,'El tipo de articulo no es valido.',1;
    IF @Tipo='SERVICIO' AND @ManejaInventario=1 THROW 52004,'Un servicio no puede manejar inventario.',1;
    IF @PorcentajeIvaVenta IS NOT NULL AND (@PorcentajeIvaVenta<0 OR @PorcentajeIvaVenta>100)
        THROW 52031,'El IVA de venta debe estar entre 0 y 100 por ciento.',1;
    IF NOT EXISTS(SELECT 1 FROM inv.UnidadMedida WHERE EmpresaId=@EmpresaId AND UnidadMedidaId=@UnidadBaseId AND Activa=1)
        THROW 52005,'La unidad base no existe o esta inactiva.',1;
    BEGIN TRANSACTION; DECLARE @Id bigint,@Creado bit=0;
    SELECT @Id=ArticuloId FROM inv.Articulo WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Codigo=@Codigo;
    IF @Id IS NULL
    BEGIN
        INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId,ManejaLote,ManejaSerial,RequiereVencimiento,PesoBaseKg,VolumenBaseM3,PorcentajeIvaVenta)
        VALUES(@EmpresaId,@Codigo,@Descripcion,@Tipo,@ManejaInventario,@UnidadBaseId,@ManejaLote,@ManejaSerial,@RequiereVencimiento,@PesoBaseKg,@VolumenBaseM3,@PorcentajeIvaVenta);
        SET @Id=SCOPE_IDENTITY(); SET @Creado=1;
    END
    ELSE UPDATE inv.Articulo SET Descripcion=@Descripcion,Tipo=@Tipo,ManejaInventario=@ManejaInventario,
        UnidadBaseId=@UnidadBaseId,ManejaLote=@ManejaLote,ManejaSerial=@ManejaSerial,
        RequiereVencimiento=@RequiereVencimiento,PesoBaseKg=@PesoBaseKg,VolumenBaseM3=@VolumenBaseM3,
        PorcentajeIvaVenta=@PorcentajeIvaVenta,Activo=1 WHERE EmpresaId=@EmpresaId AND ArticuloId=@Id;
    IF NOT EXISTS(SELECT 1 FROM inv.ArticuloUnidad WHERE EmpresaId=@EmpresaId AND ArticuloId=@Id AND UnidadMedidaId=@UnidadBaseId)
        INSERT inv.ArticuloUnidad(EmpresaId,ArticuloId,UnidadMedidaId,FactorAUnidadBase,EsUnidadCompra,EsUnidadVenta)
        VALUES(@EmpresaId,@Id,@UnidadBaseId,1,1,1);
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'ARTICULO_CREADO' ELSE 'ARTICULO_ACTUALIZADO' END,
        'inv.Articulo',CONVERT(nvarchar(100),@Id),'MAESTROS');
    COMMIT; SELECT @Id ArticuloId,@Creado Creado;
END;
GO
