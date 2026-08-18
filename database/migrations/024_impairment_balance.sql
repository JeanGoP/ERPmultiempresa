SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='024_impairment_balance')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    ALTER TABLE inv.DeterioroInventario ADD SaldoDeterioroAnterior decimal(20,4) NOT NULL CONSTRAINT DF_Deterioro_SaldoAnterior DEFAULT 0,
        SaldoDeterioroPosterior decimal(20,4) NOT NULL CONSTRAINT DF_Deterioro_SaldoPosterior DEFAULT 0,
        DeterioroRelacionadoId bigint NULL;
    ALTER TABLE inv.DeterioroInventario ADD CONSTRAINT UQ_DeterioroInventario_EmpresaId UNIQUE(EmpresaId,DeterioroInventarioId);
    ALTER TABLE inv.DeterioroInventario ADD CONSTRAINT FK_Deterioro_Relacionado FOREIGN KEY(EmpresaId,DeterioroRelacionadoId) REFERENCES inv.DeterioroInventario(EmpresaId,DeterioroInventarioId);
    CREATE TABLE inv.SaldoDeterioroInventario
    (
        EmpresaId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        DeterioroAcumulado decimal(20,4) NOT NULL,
        UltimoDeterioroInventarioId bigint NOT NULL,
        ActualizadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_SaldoDeterioro_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_SaldoDeterioroInventario PRIMARY KEY CLUSTERED(EmpresaId,BodegaId,ArticuloId),
        CONSTRAINT FK_SaldoDeterioro_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_SaldoDeterioro_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_SaldoDeterioro_Ultimo FOREIGN KEY(EmpresaId,UltimoDeterioroInventarioId) REFERENCES inv.DeterioroInventario(EmpresaId,DeterioroInventarioId),
        CONSTRAINT CK_SaldoDeterioro_Valor CHECK(DeterioroAcumulado>=0)
    );
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SaldoDeterioroInventario;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SaldoDeterioroInventario AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SaldoDeterioroInventario AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('024_impairment_balance',N'Saldo de deterioro acumulado y valor neto contable sin alterar costo histórico');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER VIEW inv.vw_ValorNetoInventario AS
SELECT s.EmpresaId,s.BodegaId,s.ArticuloId,s.Existencia,s.CostoPromedio,s.ValorTotal AS CostoHistorico,
       COALESCE(d.DeterioroAcumulado,0) DeterioroAcumulado,
       s.ValorTotal-COALESCE(d.DeterioroAcumulado,0) ValorNetoContable
FROM inv.SaldoArticuloBodega s LEFT JOIN inv.SaldoDeterioroInventario d ON d.EmpresaId=s.EmpresaId AND d.BodegaId=s.BodegaId AND d.ArticuloId=s.ArticuloId;
GO

CREATE OR ALTER PROCEDURE inv.usp_RegistrarDeterioroInventario
    @EmpresaId bigint,@BodegaId bigint,@ArticuloId bigint,@PeriodoInventarioId bigint,@Tipo varchar(20),
    @ValorNetoRealizable decimal(20,4),@Motivo nvarchar(500),@DocumentoSoporte nvarchar(100)=NULL,@UsuarioId bigint=NULL,@DeterioroRelacionadoId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    IF NOT EXISTS(SELECT 1 FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId AND Estado IN('ABIERTO','REABIERTO'))
        THROW 51910,'El periodo de inventario no está abierto.',1;
    DECLARE @CostoHistorico decimal(20,4)=(SELECT ValorTotal FROM inv.SaldoArticuloBodega WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId);
    IF @CostoHistorico IS NULL THROW 51911,'No existe saldo del artículo en la bodega.',1;
    IF @ValorNetoRealizable<0 THROW 51912,'El valor indicado no puede ser negativo.',1;
    DECLARE @SaldoAnterior decimal(20,4)=COALESCE((SELECT DeterioroAcumulado FROM inv.SaldoDeterioroInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId),0);
    DECLARE @ValorMovimiento decimal(20,4),@SaldoPosterior decimal(20,4),@VnrPosterior decimal(20,4);
    IF @Tipo='REVERSA'
    BEGIN
        SET @ValorMovimiento=@ValorNetoRealizable;
        IF @ValorMovimiento<=0 OR @ValorMovimiento>@SaldoAnterior THROW 51914,'La reversa debe ser positiva y no superar el deterioro acumulado.',1;
        SET @SaldoPosterior=@SaldoAnterior-@ValorMovimiento;
        SET @VnrPosterior=@CostoHistorico-@SaldoPosterior;
    END
    ELSE
    BEGIN
        IF @ValorNetoRealizable>@CostoHistorico THROW 51913,'El valor neto realizable no puede superar el costo histórico para registrar deterioro.',1;
        SET @SaldoPosterior=@CostoHistorico-@ValorNetoRealizable;
        SET @ValorMovimiento=@SaldoPosterior-@SaldoAnterior;
        IF @ValorMovimiento<=0 THROW 51915,'El nuevo cálculo no incrementa el deterioro; utilice una reversa para disminuirlo.',1;
        SET @VnrPosterior=@ValorNetoRealizable;
    END;
    INSERT inv.DeterioroInventario(EmpresaId,BodegaId,ArticuloId,PeriodoInventarioId,Tipo,CostoHistorico,ValorNetoRealizable,ValorDeterioro,Motivo,DocumentoSoporte,CreadoPorUsuarioId,SaldoDeterioroAnterior,SaldoDeterioroPosterior,DeterioroRelacionadoId)
    VALUES(@EmpresaId,@BodegaId,@ArticuloId,@PeriodoInventarioId,@Tipo,@CostoHistorico,@VnrPosterior,@ValorMovimiento,@Motivo,@DocumentoSoporte,@UsuarioId,@SaldoAnterior,@SaldoPosterior,@DeterioroRelacionadoId);
    DECLARE @Id bigint=SCOPE_IDENTITY();
    UPDATE inv.SaldoDeterioroInventario SET DeterioroAcumulado=@SaldoPosterior,UltimoDeterioroInventarioId=@Id,ActualizadoEnUtc=SYSUTCDATETIME()
    WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId;
    IF @@ROWCOUNT=0 INSERT inv.SaldoDeterioroInventario(EmpresaId,BodegaId,ArticuloId,DeterioroAcumulado,UltimoDeterioroInventarioId) VALUES(@EmpresaId,@BodegaId,@ArticuloId,@SaldoPosterior,@Id);
    INSERT core.OutboxEvento(EmpresaId,TipoEvento,TipoAgregado,AgregadoId,Payload)
    VALUES(@EmpresaId,N'Inventario.DeterioroRegistrado',N'DeterioroInventario',CONVERT(nvarchar(100),@Id),CONCAT(N'{"deterioroId":',@Id,N',"tipo":"',@Tipo,N'","movimiento":',CONVERT(varchar(50),@ValorMovimiento),N',"saldoAnterior":',CONVERT(varchar(50),@SaldoAnterior),N',"saldoPosterior":',CONVERT(varchar(50),@SaldoPosterior),N'}'));
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'DETERIORO_INVENTARIO_REGISTRADO','inv.DeterioroInventario',CONVERT(nvarchar(100),@Id),CONCAT(N'{"deterioroAcumulado":',@SaldoAnterior,N'}'),CONCAT(N'{"deterioroAcumulado":',@SaldoPosterior,N',"valorNetoContable":',@CostoHistorico-@SaldoPosterior,N'}'),'INVENTARIO');
    COMMIT;
    SELECT @Id DeterioroInventarioId,@CostoHistorico CostoHistorico,@ValorMovimiento ValorDeterioro,@SaldoPosterior DeterioroAcumulado,@CostoHistorico-@SaldoPosterior ValorNetoContable;
END;
GO
