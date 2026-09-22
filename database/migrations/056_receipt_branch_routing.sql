SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='056_receipt_branch_routing')
BEGIN
 ALTER TABLE inv.Bodega ADD SucursalId bigint NULL;
 ALTER TABLE inv.Bodega ADD CONSTRAINT FK_Bodega_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId);
 ALTER TABLE inv.RecepcionMercancia ADD SucursalId bigint NULL;
 ALTER TABLE inv.RecepcionMercancia ADD CONSTRAINT FK_Recepcion_Sucursal FOREIGN KEY(EmpresaId,SucursalId) REFERENCES core.Sucursal(EmpresaId,SucursalId);
 INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('056_receipt_branch_routing',N'Sucursal de bodega y sucursal contable congelada en entradas');
END;
GO
CREATE OR ALTER PROCEDURE inv.usp_GuardarBodega
 @EmpresaId bigint,@Codigo nvarchar(30),@Nombre nvarchar(120),@UsaUbicaciones bit=0,@EsTransito bit=0,@UsuarioId bigint,@SucursalId bigint=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRANSACTION;
 DECLARE @Id bigint,@Creado bit=0;
 SELECT @Id=BodegaId,@SucursalId=COALESCE(@SucursalId,SucursalId) FROM inv.Bodega WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND Codigo=@Codigo;
 IF @SucursalId IS NULL OR NOT EXISTS(SELECT 1 FROM core.Sucursal WITH(HOLDLOCK) WHERE EmpresaId=@EmpresaId AND SucursalId=@SucursalId AND Activa=1)
  THROW 52030,'Selecciona una sucursal activa de esta empresa para la bodega.',1;
 IF @Id IS NULL BEGIN
  INSERT inv.Bodega(EmpresaId,Codigo,Nombre,UsaUbicaciones,EsTransito,SucursalId) VALUES(@EmpresaId,@Codigo,@Nombre,@UsaUbicaciones,@EsTransito,@SucursalId);
  SET @Id=SCOPE_IDENTITY(); SET @Creado=1;
 END
 ELSE UPDATE inv.Bodega SET Nombre=@Nombre,UsaUbicaciones=@UsaUbicaciones,EsTransito=@EsTransito,Activa=1,SucursalId=@SucursalId WHERE EmpresaId=@EmpresaId AND BodegaId=@Id;
 INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
 VALUES(@EmpresaId,@UsuarioId,CASE WHEN @Creado=1 THEN 'BODEGA_CREADA' ELSE 'BODEGA_ACTUALIZADA' END,'inv.Bodega',CONVERT(nvarchar(100),@Id),(SELECT @SucursalId sucursalId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'MAESTROS');
 COMMIT; SELECT @Id BodegaId,@Creado Creado;
END;
GO
CREATE OR ALTER TRIGGER inv.TR_Recepcion_Sucursal ON inv.RecepcionMercancia AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON i.RecepcionMercanciaId=d.RecepcionMercanciaId WHERE d.SucursalId IS NOT NULL AND (i.SucursalId IS NULL OR i.SucursalId<>d.SucursalId))
  THROW 52031,'La sucursal contable de la entrada ya esta fijada y no puede cambiarse.',1;
END;
GO
COMMIT;
