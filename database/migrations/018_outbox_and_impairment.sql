SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='018_outbox_and_impairment')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE core.OutboxEvento
    (
        OutboxEventoId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        EventoGuid uniqueidentifier NOT NULL CONSTRAINT DF_OutboxEvento_Guid DEFAULT NEWSEQUENTIALID(),
        TipoEvento nvarchar(120) NOT NULL,
        TipoAgregado nvarchar(100) NOT NULL,
        AgregadoId nvarchar(100) NOT NULL,
        Payload nvarchar(max) NOT NULL,
        OcurridoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_OutboxEvento_Ocurrido DEFAULT SYSUTCDATETIME(),
        DisponibleEnUtc datetime2(7) NOT NULL CONSTRAINT DF_OutboxEvento_Disponible DEFAULT SYSUTCDATETIME(),
        ProcesadoEnUtc datetime2(7) NULL,
        Intentos int NOT NULL CONSTRAINT DF_OutboxEvento_Intentos DEFAULT 0,
        UltimoError nvarchar(2000) NULL,
        CONSTRAINT PK_OutboxEvento PRIMARY KEY CLUSTERED(OutboxEventoId),
        CONSTRAINT UQ_OutboxEvento_Guid UNIQUE(EventoGuid),
        CONSTRAINT FK_OutboxEvento_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_OutboxEvento_Payload CHECK(ISJSON(Payload)=1),
        CONSTRAINT CK_OutboxEvento_Intentos CHECK(Intentos>=0)
    );
    CREATE INDEX IX_OutboxEvento_Pendiente ON core.OutboxEvento(ProcesadoEnUtc,DisponibleEnUtc,OutboxEventoId) INCLUDE(EmpresaId,TipoEvento,Intentos) WHERE ProcesadoEnUtc IS NULL;
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.OutboxEvento;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.OutboxEvento AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON core.OutboxEvento AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('018_outbox_and_impairment',N'Outbox transaccional y registro ejecutable de deterioro de inventario');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventario_Outbox ON inv.MovimientoInventario AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT core.OutboxEvento(EmpresaId,TipoEvento,TipoAgregado,AgregadoId,Payload)
    SELECT EmpresaId,N'Inventario.MovimientoRegistrado',N'MovimientoInventario',CONVERT(nvarchar(100),MovimientoInventarioId),
        CONCAT(N'{"movimientoId":',MovimientoInventarioId,N',"bodegaId":',BodegaId,N',"articuloId":',ArticuloId,N',"entrada":',CONVERT(varchar(50),CantidadEntrada),N',"salida":',CONVERT(varchar(50),CantidadSalida),N',"valor":',CONVERT(varchar(50),ValorMovimiento),N',"tipo":"',TipoMovimiento,N'"}')
    FROM inserted;
END;
GO

CREATE OR ALTER TRIGGER cont.TR_ComprobanteContable_Outbox ON cont.ComprobanteContable AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT core.OutboxEvento(EmpresaId,TipoEvento,TipoAgregado,AgregadoId,Payload)
    SELECT EmpresaId,N'Contabilidad.ComprobanteContabilizado',N'ComprobanteContable',CONVERT(nvarchar(100),ComprobanteContableId),
        CONCAT(N'{"comprobanteId":',ComprobanteContableId,N',"numero":"',STRING_ESCAPE(Numero,'json'),N'","debito":',CONVERT(varchar(50),TotalDebito),N',"credito":',CONVERT(varchar(50),TotalCredito),N'}')
    FROM inserted;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_RegistrarDeterioroInventario
    @EmpresaId bigint,@BodegaId bigint,@ArticuloId bigint,@PeriodoInventarioId bigint,@Tipo varchar(20),
    @ValorNetoRealizable decimal(20,4),@Motivo nvarchar(500),@DocumentoSoporte nvarchar(100)=NULL,@UsuarioId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    IF NOT EXISTS(SELECT 1 FROM core.PeriodoInventario WHERE EmpresaId=@EmpresaId AND PeriodoInventarioId=@PeriodoInventarioId AND Estado IN('ABIERTO','REABIERTO'))
        THROW 51910,'El periodo de inventario no está abierto.',1;
    DECLARE @CostoHistorico decimal(20,4)=(SELECT ValorTotal FROM inv.SaldoArticuloBodega WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId);
    IF @CostoHistorico IS NULL THROW 51911,'No existe saldo del artículo en la bodega.',1;
    IF @ValorNetoRealizable<0 THROW 51912,'El valor neto realizable no puede ser negativo.',1;
    DECLARE @ValorDeterioro decimal(20,4)=CASE WHEN @Tipo='REVERSA' THEN @ValorNetoRealizable ELSE @CostoHistorico-@ValorNetoRealizable END;
    IF @ValorDeterioro<0 THROW 51913,'El valor neto realizable no puede superar el costo histórico para este tipo de registro.',1;
    INSERT inv.DeterioroInventario(EmpresaId,BodegaId,ArticuloId,PeriodoInventarioId,Tipo,CostoHistorico,ValorNetoRealizable,ValorDeterioro,Motivo,DocumentoSoporte,CreadoPorUsuarioId)
    VALUES(@EmpresaId,@BodegaId,@ArticuloId,@PeriodoInventarioId,@Tipo,@CostoHistorico,@ValorNetoRealizable,@ValorDeterioro,@Motivo,@DocumentoSoporte,@UsuarioId);
    DECLARE @Id bigint=SCOPE_IDENTITY();
    INSERT core.OutboxEvento(EmpresaId,TipoEvento,TipoAgregado,AgregadoId,Payload)
    VALUES(@EmpresaId,N'Inventario.DeterioroRegistrado',N'DeterioroInventario',CONVERT(nvarchar(100),@Id),CONCAT(N'{"deterioroId":',@Id,N',"tipo":"',@Tipo,N'","valor":',CONVERT(varchar(50),@ValorDeterioro),N'}'));
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
    VALUES(@EmpresaId,@UsuarioId,'DETERIORO_INVENTARIO_REGISTRADO','inv.DeterioroInventario',CONVERT(nvarchar(100),@Id),CONCAT(N'{"tipo":"',@Tipo,N'","valor":',CONVERT(varchar(50),@ValorDeterioro),N'}'),'INVENTARIO');
    COMMIT;
    SELECT @Id DeterioroInventarioId,@CostoHistorico CostoHistorico,@ValorDeterioro ValorDeterioro;
END;
GO
