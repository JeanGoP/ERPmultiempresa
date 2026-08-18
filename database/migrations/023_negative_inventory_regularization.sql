SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='023_negative_inventory_regularization')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.SalidaExcepcionalNegativa
    (
        SalidaExcepcionalNegativaId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        IdempotencyKey uniqueidentifier NOT NULL,
        MovimientoDisponibleKey uniqueidentifier NOT NULL CONSTRAINT DF_SalidaNegativa_DisponibleKey DEFAULT NEWID(),
        MovimientoRegularizacionKey uniqueidentifier NOT NULL CONSTRAINT DF_SalidaNegativa_RegularizacionKey DEFAULT NEWID(),
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        PeriodoInventarioId bigint NOT NULL,
        FechaMovimiento datetime2(7) NOT NULL,
        FechaContable date NOT NULL,
        TipoDocumentoOrigen varchar(40) NOT NULL,
        DocumentoOrigenId bigint NOT NULL,
        NumeroDocumento nvarchar(50) NOT NULL,
        CantidadSolicitada decimal(20,6) NOT NULL,
        CantidadValorizada decimal(20,6) NOT NULL,
        CantidadPendiente decimal(20,6) NOT NULL,
        Motivo nvarchar(500) NOT NULL,
        AutorizadoPorUsuarioId bigint NOT NULL,
        MovimientoDisponibleId bigint NULL,
        RecepcionMercanciaLineaId bigint NULL,
        MovimientoRegularizacionId bigint NULL,
        Estado varchar(15) NOT NULL,
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_SalidaNegativa_Fecha DEFAULT SYSUTCDATETIME(),
        RegularizadoEnUtc datetime2(7) NULL,
        CONSTRAINT PK_SalidaExcepcionalNegativa PRIMARY KEY CLUSTERED(SalidaExcepcionalNegativaId),
        CONSTRAINT UQ_SalidaExcepcionalNegativa_EmpresaId UNIQUE(EmpresaId,SalidaExcepcionalNegativaId),
        CONSTRAINT UQ_SalidaExcepcionalNegativa_Key UNIQUE(EmpresaId,IdempotencyKey),
        CONSTRAINT UQ_SalidaExcepcionalNegativa_MovDisponibleKey UNIQUE(EmpresaId,MovimientoDisponibleKey),
        CONSTRAINT UQ_SalidaExcepcionalNegativa_MovRegularizacionKey UNIQUE(EmpresaId,MovimientoRegularizacionKey),
        CONSTRAINT FK_SalidaExcepcionalNegativa_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_SalidaExcepcionalNegativa_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT FK_SalidaExcepcionalNegativa_Periodo FOREIGN KEY(EmpresaId,PeriodoInventarioId) REFERENCES core.PeriodoInventario(EmpresaId,PeriodoInventarioId),
        CONSTRAINT FK_SalidaExcepcionalNegativa_Usuario FOREIGN KEY(AutorizadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT FK_SalidaExcepcionalNegativa_MovDisponible FOREIGN KEY(EmpresaId,MovimientoDisponibleId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT FK_SalidaExcepcionalNegativa_Recepcion FOREIGN KEY(EmpresaId,RecepcionMercanciaLineaId) REFERENCES inv.RecepcionMercanciaLinea(EmpresaId,RecepcionMercanciaLineaId),
        CONSTRAINT FK_SalidaExcepcionalNegativa_MovRegularizacion FOREIGN KEY(EmpresaId,MovimientoRegularizacionId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId),
        CONSTRAINT CK_SalidaExcepcionalNegativa_Cantidades CHECK(CantidadSolicitada>0 AND CantidadValorizada>=0 AND CantidadPendiente>0 AND CantidadValorizada+CantidadPendiente=CantidadSolicitada),
        CONSTRAINT CK_SalidaExcepcionalNegativa_Estado CHECK(Estado IN('PENDIENTE','REGULARIZADA','CANCELADA'))
    );
    CREATE INDEX IX_SalidaExcepcionalNegativa_Pendiente ON inv.SalidaExcepcionalNegativa(EmpresaId,BodegaId,ArticuloId,Estado,CreadoEnUtc) INCLUDE(CantidadPendiente) WHERE Estado='PENDIENTE';
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SalidaExcepcionalNegativa;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SalidaExcepcionalNegativa AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.SalidaExcepcionalNegativa AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('023_negative_inventory_regularization',N'Salidas excepcionales no valorizadas y regularización al costo real posterior');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER VIEW inv.vw_DisponibilidadArticuloBodega AS
SELECT s.EmpresaId,s.BodegaId,s.ArticuloId,s.Existencia AS ExistenciaValorizada,
       COALESCE(p.CantidadPendiente,0) AS SalidaPendienteRegularizar,
       s.Existencia-COALESCE(p.CantidadPendiente,0) AS DisponibilidadOperativa,
       s.CostoPromedio,s.ValorTotal
FROM inv.SaldoArticuloBodega s
OUTER APPLY(SELECT SUM(CantidadPendiente) CantidadPendiente FROM inv.SalidaExcepcionalNegativa p WHERE p.EmpresaId=s.EmpresaId AND p.BodegaId=s.BodegaId AND p.ArticuloId=s.ArticuloId AND p.Estado='PENDIENTE') p;
GO

CREATE OR ALTER PROCEDURE inv.usp_RegistrarSalidaExcepcionalNegativa
    @EmpresaId bigint,@BodegaId bigint,@ArticuloId bigint,@PeriodoInventarioId bigint,@FechaMovimiento datetime2(7),@FechaContable date,
    @TipoDocumentoOrigen varchar(40),@DocumentoOrigenId bigint,@NumeroDocumento nvarchar(50),@CantidadSolicitada decimal(20,6),
    @Motivo nvarchar(500),@AutorizadoPorUsuarioId bigint,@IdempotencyKey uniqueidentifier,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CantidadSolicitada<=0 THROW 51970,'La cantidad solicitada debe ser positiva.',1;
    IF LEN(LTRIM(RTRIM(@Motivo)))<10 THROW 51971,'La salida excepcional requiere un motivo suficiente.',1;
    DECLARE @ExistenteId bigint=(SELECT SalidaExcepcionalNegativaId FROM inv.SalidaExcepcionalNegativa WHERE EmpresaId=@EmpresaId AND IdempotencyKey=@IdempotencyKey);
    IF @ExistenteId IS NOT NULL BEGIN SELECT SalidaExcepcionalNegativaId,Estado,CantidadValorizada,CantidadPendiente,CAST(1 AS bit) YaExistia FROM inv.SalidaExcepcionalNegativa WHERE EmpresaId=@EmpresaId AND SalidaExcepcionalNegativaId=@ExistenteId; RETURN; END;
    BEGIN TRANSACTION;
    IF NOT EXISTS(SELECT 1 FROM core.EmpresaConfiguracion WHERE EmpresaId=@EmpresaId AND PermiteInventarioNegativo=1) THROW 51972,'La empresa no permite el flujo excepcional de inventario negativo.',1;
    IF NOT EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@AutorizadoPorUsuarioId AND Activo=1) THROW 51973,'El autorizador no tiene acceso activo a la empresa.',1;
    DECLARE @Disponible decimal(20,6)=COALESCE((SELECT Existencia FROM inv.SaldoArticuloBodega WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId),0);
    DECLARE @Valorizada decimal(20,6)=CASE WHEN @Disponible>@CantidadSolicitada THEN @CantidadSolicitada ELSE @Disponible END;
    DECLARE @Pendiente decimal(20,6)=@CantidadSolicitada-@Valorizada,@SalidaId bigint,@SalidaKey uniqueidentifier=NEWID();
    IF @Pendiente<=0 THROW 51974,'Existe inventario suficiente; utilice el flujo normal de salida.',1;
    INSERT inv.SalidaExcepcionalNegativa(EmpresaId,IdempotencyKey,MovimientoDisponibleKey,MovimientoRegularizacionKey,BodegaId,ArticuloId,PeriodoInventarioId,FechaMovimiento,FechaContable,TipoDocumentoOrigen,DocumentoOrigenId,NumeroDocumento,CantidadSolicitada,CantidadValorizada,CantidadPendiente,Motivo,AutorizadoPorUsuarioId,Estado)
    VALUES(@EmpresaId,@IdempotencyKey,@SalidaKey,NEWID(),@BodegaId,@ArticuloId,@PeriodoInventarioId,@FechaMovimiento,@FechaContable,@TipoDocumentoOrigen,@DocumentoOrigenId,@NumeroDocumento,@CantidadSolicitada,@Valorizada,@Pendiente,@Motivo,@AutorizadoPorUsuarioId,'PENDIENTE');
    DECLARE @Id bigint=SCOPE_IDENTITY();
    IF @Valorizada>0
    BEGIN
        DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
        INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaMovimiento,@FechaContable=@FechaContable,@TipoMovimiento='SALIDA_EXCEPCIONAL',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen=@TipoDocumentoOrigen,@DocumentoOrigenId=@DocumentoOrigenId,@DocumentoLineaOrigenId=@Id,@NumeroDocumento=@NumeroDocumento,@CantidadSalida=@Valorizada,@IdempotencyKey=@SalidaKey,@UsuarioId=@AutorizadoPorUsuarioId,@CorrelationId=@CorrelationId;
        SELECT @SalidaId=MovimientoInventarioId FROM @R;
        UPDATE inv.SalidaExcepcionalNegativa SET MovimientoDisponibleId=@SalidaId WHERE EmpresaId=@EmpresaId AND SalidaExcepcionalNegativaId=@Id;
    END;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@AutorizadoPorUsuarioId,'SALIDA_NEGATIVA_PENDIENTE','inv.SalidaExcepcionalNegativa',CONVERT(nvarchar(100),@Id),@NumeroDocumento,CONCAT(N'{"solicitada":',@CantidadSolicitada,N',"valorizada":',@Valorizada,N',"pendiente":',@Pendiente,N'}'),'INVENTARIO',@CorrelationId);
    COMMIT;
    SELECT @Id SalidaExcepcionalNegativaId,CAST('PENDIENTE' AS varchar(15)) Estado,@Valorizada CantidadValorizada,@Pendiente CantidadPendiente,CAST(0 AS bit) YaExistia;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_RegularizarSalidaExcepcionalNegativa
    @EmpresaId bigint,@SalidaExcepcionalNegativaId bigint,@RecepcionMercanciaLineaId bigint,@PeriodoInventarioId bigint,@FechaContable date,
    @UsuarioId bigint=NULL,@CorrelationId uniqueidentifier=NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DECLARE @Estado varchar(15),@BodegaId bigint,@ArticuloId bigint,@Pendiente decimal(20,6),@Numero nvarchar(50),@Key uniqueidentifier,@Costo decimal(20,8),@OrigenId bigint,@MovimientoRecepcionId bigint;
    SELECT @Estado=Estado,@BodegaId=BodegaId,@ArticuloId=ArticuloId,@Pendiente=CantidadPendiente,@Numero=NumeroDocumento,@Key=MovimientoRegularizacionKey
    FROM inv.SalidaExcepcionalNegativa WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND SalidaExcepcionalNegativaId=@SalidaExcepcionalNegativaId;
    IF @Estado IS NULL THROW 51975,'La salida excepcional no existe.',1;
    IF @Estado='REGULARIZADA' BEGIN COMMIT; SELECT @SalidaExcepcionalNegativaId SalidaExcepcionalNegativaId,@Estado Estado,CAST(1 AS bit) YaExistia; RETURN; END;
    IF @Estado<>'PENDIENTE' THROW 51976,'La salida excepcional no está pendiente.',1;
    SELECT @Costo=CAST(r.CostoTotalCapitalizable/r.CantidadBase AS decimal(20,8)),@MovimientoRecepcionId=m.MovimientoInventarioId,@OrigenId=o.OrigenInventarioId
    FROM inv.RecepcionMercanciaLinea r JOIN inv.RecepcionMercancia h ON h.EmpresaId=r.EmpresaId AND h.RecepcionMercanciaId=r.RecepcionMercanciaId AND h.Estado='CONTABILIZADA'
    JOIN inv.MovimientoInventario m ON m.EmpresaId=r.EmpresaId AND m.TipoDocumentoOrigen='RECEPCION_MERCANCIA' AND m.DocumentoLineaOrigenId=r.RecepcionMercanciaLineaId
    JOIN inv.OrigenInventario o ON o.EmpresaId=r.EmpresaId AND o.RecepcionMercanciaLineaId=r.RecepcionMercanciaLineaId
    WHERE r.EmpresaId=@EmpresaId AND r.RecepcionMercanciaLineaId=@RecepcionMercanciaLineaId AND r.ArticuloId=@ArticuloId AND h.BodegaId=@BodegaId;
    IF @OrigenId IS NULL THROW 51977,'La recepción no está contabilizada en la misma bodega y artículo.',1;
    IF COALESCE((SELECT CantidadDisponible FROM inv.SaldoOrigenBodega WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenId),0)<@Pendiente
        THROW 51978,'La recepción seleccionada no tiene cantidad de origen suficiente para regularizar.',1;
    BEGIN TRY
        EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=1;
        DECLARE @R TABLE(MovimientoInventarioId bigint,ExistenciaPosterior decimal(20,6),CostoPromedioPosterior decimal(20,8),ValorTotalPosterior decimal(20,4),YaExistia bit);
        INSERT @R EXEC inv.usp_ContabilizarSalida @EmpresaId=@EmpresaId,@BodegaId=@BodegaId,@ArticuloId=@ArticuloId,@PeriodoInventarioId=@PeriodoInventarioId,@FechaMovimiento=@FechaContable,@FechaContable=@FechaContable,@TipoMovimiento='REGULARIZACION_NEGATIVO',@ModuloOrigen='INVENTARIO',@TipoDocumentoOrigen='REGULARIZACION_NEGATIVO',@DocumentoOrigenId=@SalidaExcepcionalNegativaId,@DocumentoLineaOrigenId=@SalidaExcepcionalNegativaId,@NumeroDocumento=@Numero,@CantidadSalida=@Pendiente,@IdempotencyKey=@Key,@UsuarioId=@UsuarioId,@CorrelationId=@CorrelationId,@MovimientoRelacionadoId=@MovimientoRecepcionId,@CostoUnitarioForzado=@Costo;
        EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=NULL;
        DECLARE @MovimientoId bigint=(SELECT MovimientoInventarioId FROM @R);
        UPDATE inv.SaldoOrigenBodega SET CantidadDisponible=CantidadDisponible-@Pendiente,ActualizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND BodegaId=@BodegaId AND ArticuloId=@ArticuloId AND OrigenInventarioId=@OrigenId;
        INSERT inv.MovimientoOrigenInventario(EmpresaId,MovimientoInventarioId,OrigenInventarioId,CantidadSalida) VALUES(@EmpresaId,@MovimientoId,@OrigenId,@Pendiente);
        UPDATE inv.SalidaExcepcionalNegativa SET Estado='REGULARIZADA',RecepcionMercanciaLineaId=@RecepcionMercanciaLineaId,MovimientoRegularizacionId=@MovimientoId,RegularizadoEnUtc=SYSUTCDATETIME() WHERE EmpresaId=@EmpresaId AND SalidaExcepcionalNegativaId=@SalidaExcepcionalNegativaId;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key=N'OmitirOrigenAutomatico',@value=NULL;
        THROW;
    END CATCH;
    INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,DocumentoNumero,ValoresPosteriores,AplicacionOrigen,CorrelationId)
    VALUES(@EmpresaId,@UsuarioId,'SALIDA_NEGATIVA_REGULARIZADA','inv.SalidaExcepcionalNegativa',CONVERT(nvarchar(100),@SalidaExcepcionalNegativaId),@Numero,CONCAT(N'{"recepcionLineaId":',@RecepcionMercanciaLineaId,N',"cantidad":',@Pendiente,N',"costo":',@Costo,N'}'),'INVENTARIO',@CorrelationId);
    COMMIT;
    SELECT @SalidaExcepcionalNegativaId SalidaExcepcionalNegativaId,CAST('REGULARIZADA' AS varchar(15)) Estado,CAST(0 AS bit) YaExistia;
END;
GO
