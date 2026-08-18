namespace NexoERP.Api.Inventory;

public sealed record WarehouseResponse(long BodegaId, string Codigo, string Nombre, bool UsaUbicaciones, bool EsTransito);
public sealed record InventoryPeriodListResponse(long PeriodoInventarioId,string Codigo,DateOnly FechaInicio,DateOnly FechaFin,string Estado);

public sealed record InventoryBalanceResponse(
    long BodegaId, string Bodega, long ArticuloId, string Codigo, string Descripcion,
    decimal Existencia, decimal ValorTotal, decimal CostoPromedio);

public sealed record DetailedInventoryBalanceResponse(
    long BodegaId,string Bodega,long? UbicacionId,string? Ubicacion,long ArticuloId,string Codigo,string Descripcion,
    long? LoteId,string? NumeroLote,DateOnly? FechaVencimiento,decimal Existencia,decimal ValorTotal,decimal CostoPromedio);

public sealed record KardexMovementResponse(
    long MovimientoInventarioId,DateTime FechaMovimiento,DateOnly FechaContable,string TipoMovimiento,string NumeroDocumento,
    long BodegaId,string Bodega,long ArticuloId,string Codigo,string Descripcion,string? NumeroLote,
    decimal Entrada,decimal Salida,decimal CostoUnitario,decimal ValorMovimiento,decimal ExistenciaPosterior,decimal CostoPromedioPosterior);

public sealed record ExpiryAlertResponse(
    long BodegaId,string Bodega,long ArticuloId,string Codigo,string Descripcion,long LoteId,string NumeroLote,
    DateOnly FechaVencimiento,int DiasParaVencer,string Estado,decimal Existencia);

public sealed record PostInventoryEntryRequest(
    long BodegaId,
    long? UbicacionId,
    long ArticuloId,
    long? LoteId,
    long PeriodoInventarioId,
    DateTime FechaMovimiento,
    DateOnly FechaContable,
    string TipoMovimiento,
    string ModuloOrigen,
    string TipoDocumentoOrigen,
    long DocumentoOrigenId,
    long? DocumentoLineaOrigenId,
    string NumeroDocumento,
    long? TerceroId,
    decimal Cantidad,
    decimal CostoUnitario,
    Guid IdempotencyKey,
    long? UsuarioId,
    Guid? CorrelationId,
    long? MovimientoRelacionadoId);

public sealed record InventoryMovementResponse(
    long MovimientoInventarioId,
    decimal ExistenciaPosterior,
    decimal CostoPromedioPosterior,
    decimal ValorTotalPosterior,
    bool YaExistia);

public sealed record HistoricalInventoryResponse(long BodegaId,long ArticuloId,string Codigo,string Descripcion,decimal Existencia,decimal ValorHistorico,decimal CostoPromedioHistorico);
public sealed record SerializedUnitResponse(long UnidadSerializadaId,Guid UnidadGuid,long ArticuloId,string Codigo,string Descripcion,string Estado,long? BodegaActualId,string? Bodega,string? Serial,string? Motor,string? Chasis,string? Vin,string? Placa);
