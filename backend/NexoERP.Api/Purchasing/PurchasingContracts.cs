namespace NexoERP.Api.Purchasing;

public sealed record SupplierDocumentSerialRequest(
    int NumeroUnidad,
    string? Serial,
    string? Motor,
    string? Chasis,
    string? Vin,
    string? Color,
    string? Modelo,
    string? InformacionOriginal);

public sealed record SupplierDocumentLineRequest(
    int NumeroLinea,
    long? ArticuloId,
    string? CodigoExterno,
    string Descripcion,
    string Clasificacion,
    decimal Cantidad,
    long? UnidadMedidaId,
    string? UnidadCodigo,
    bool ManejaSerial,
    decimal FactorAUnidadBase,
    decimal PrecioUnitario,
    decimal SubtotalBruto,
    decimal Descuento,
    decimal Impuesto,
    decimal Cargo,
    decimal Retencion,
    decimal TotalNeto,
    string? NumeroLote,
    DateOnly? FechaVencimiento,
    IReadOnlyList<SupplierDocumentSerialRequest>? Seriales);

public sealed record CreateSupplierDocumentRequest(
    string ProveedorIdentificacion,
    string ProveedorRazonSocial,
    string? ProveedorTipoIdentificacion,
    string? ProveedorDigitoVerificacion,
    string? ProveedorNombreComercial,
    string? ProveedorResponsabilidadFiscal,
    string? ProveedorRegimenFiscalCodigo,
    string? ProveedorRegimenFiscalNombre,
    string? ProveedorDireccion,
    string? ProveedorCiudadCodigo,
    string? ProveedorCiudad,
    string? ProveedorDepartamentoCodigo,
    string? ProveedorDepartamento,
    string? ProveedorCodigoPostal,
    string? ProveedorPaisCodigo,
    string? ProveedorPais,
    string? ProveedorContactoNombre,
    string? ProveedorTelefono,
    string? ProveedorCorreo,
    string? ProveedorSitioWeb,
    string? ProveedorDatosXmlJson,
    string TipoDocumento,
    string NumeroDocumento,
    DateOnly FechaDocumento,
    DateOnly? FechaVencimiento,
    string CondicionPago,
    int DiasCredito,
    bool CrearArticulosFaltantes,
    string Moneda,
    string? CufeCude,
    string Fuente,
    decimal SubtotalBruto,
    decimal DescuentoTotal,
    decimal ImpuestoTotal,
    decimal CargoTotal,
    decimal TotalPagar,
    string? XmlOriginal,
    long? UsuarioId,
    Guid? DocumentoGuid,
    IReadOnlyList<SupplierDocumentLineRequest> Lineas,
    bool PrepararProcesos = false,
    long? BodegaId = null,
    long? PeriodoInventarioId = null,
    DateOnly? FechaContable = null,
    string? NumeroRecepcion = null,
    string? NumeroCausacion = null);

public sealed record SupplierDocumentResponse(
    long DocumentoProveedorId,
    bool YaExistia,
    int ArticulosCreados,
    long? RecepcionMercanciaId = null,
    long? CausacionServicioId = null);

public sealed record SupplierPayableSummaryResponse(
    int Facturas,
    int FacturasVencidas,
    decimal SaldoTotal,
    decimal SaldoVencido,
    decimal SaldoPorVencer);

public sealed record SupplierPayableItemResponse(
    long DocumentoPorPagarId,
    long DocumentoProveedorId,
    long TerceroId,
    string Proveedor,
    string ProveedorIdentificacion,
    string TipoDocumento,
    string NumeroDocumento,
    DateOnly FechaDocumento,
    DateOnly FechaReconocimiento,
    DateOnly FechaVencimiento,
    string CondicionPago,
    string Moneda,
    decimal ValorOriginal,
    decimal SaldoPendiente,
    string Estado,
    int DiasVencida,
    string RangoEdad);

public sealed record SupplierAccountsPayableResponse(
    SupplierPayableSummaryResponse Resumen,
    IReadOnlyList<SupplierPayableItemResponse> Documentos);

public sealed record SupplierStatementMovement(long MovimientoId,long DocumentoPorPagarId,string Factura,
    string TipoMovimiento,DateOnly Fecha,string Soporte,string Moneda,decimal Cargo,decimal Abono);
public sealed record SupplierStatementResponse(string Empresa,string Nit,string Proveedor,string Identificacion,
    DateTime GeneradoEnUtc,IReadOnlyList<SupplierPayableItemResponse> Facturas,IReadOnlyList<SupplierStatementMovement> Movimientos);

public sealed record SupplierDocumentListItemResponse(
    long DocumentoProveedorId,string Estado,string TipoDocumento,string NumeroDocumento,string Proveedor,
    string ProveedorIdentificacion,DateOnly FechaDocumento,DateOnly? FechaVencimiento,string CondicionPago,string Moneda,
    decimal TotalPagar,int Lineas,int UnidadesSerializadas,string Fuente,DateTime CreadoEnUtc,
    long? RecepcionMercanciaId,string? RecepcionEstado,string? Bodega);

public sealed record SupplierDocumentSerialDetailResponse(
    int NumeroUnidad,string? Serial,string? Motor,string? Chasis,string? Vin,string? Color,string? Modelo,string? InformacionOriginal);

public sealed record SupplierDocumentLineDetailResponse(
    long DocumentoProveedorLineaId,int NumeroLinea,long? ArticuloId,string? CodigoArticulo,string? CodigoExterno,
    string Descripcion,string Clasificacion,decimal Cantidad,string? Unidad,decimal PrecioUnitario,decimal SubtotalBruto,
    decimal Descuento,decimal Impuesto,decimal Retencion,decimal Cargo,decimal TotalNeto,
    IReadOnlyList<SupplierDocumentSerialDetailResponse> Seriales);

public sealed record SupplierDocumentDetailResponse(
    SupplierDocumentWorkflowResponse Documento,IReadOnlyList<SupplierDocumentLineDetailResponse> Lineas);

public sealed record RejectSupplierDocumentResponse(long DocumentoProveedorId,string Estado,bool YaExistia);

public sealed record SupplierDocumentWorkflowResponse(
    long DocumentoProveedorId,string Estado,string TipoDocumento,string NumeroDocumento,string Proveedor,
    string ProveedorIdentificacion,DateOnly FechaDocumento,DateOnly? FechaVencimiento,string CondicionPago,int DiasCredito,string Moneda,
    string? CufeCude,string? HashXml,bool XmlOriginalGuardado,decimal SubtotalBruto,decimal DescuentoTotal,
    decimal ImpuestoTotal,decimal CargoTotal,decimal TotalPagar,int Lineas,int UnidadesSerializadas,
    long? RecepcionMercanciaId,string? RecepcionNumero,string? RecepcionEstado,
    long? CausacionServicioId,string? CausacionNumero,string? CausacionEstado);

public sealed record PrepareSupplierDocumentRequest(
    long? BodegaId,
    long? PeriodoInventarioId,
    DateOnly FechaContable,
    string? NumeroRecepcion,
    string? NumeroCausacion,
    long? UsuarioId);

public sealed record PreparedSupplierDocumentResponse(
    long DocumentoProveedorId,
    long? RecepcionMercanciaId,
    long? CausacionServicioId,
    int LineasInventario,
    int LineasServicio);

public sealed record PostReceiptRequest(long? UsuarioId, Guid? CorrelationId);
public sealed record PostedReceiptResponse(long RecepcionMercanciaId, string Estado, int Movimientos, bool YaExistia);
public sealed record ReceiptMovementResponse(
    long MovimientoInventarioId,int NumeroLinea,string CodigoArticulo,string Descripcion,
    decimal CantidadEntrada,decimal CostoUnitario,decimal ValorMovimiento,decimal ExistenciaPosterior,
    decimal CostoPromedioPosterior,string Bodega,string? NumeroLote,DateOnly? FechaVencimiento,DateOnly FechaContable);

public sealed record WarehouseReceiptListItemResponse(
    long RecepcionMercanciaId,string Numero,string Estado,long DocumentoProveedorId,string TipoDocumento,string NumeroDocumento,
    string Proveedor,DateOnly FechaDocumento,DateOnly FechaContable,string Bodega,int Lineas,int UnidadesSerializadas,
    int Revisadas,int RecibidasConforme,int RecibidasConNovedad,int NoRecibidas);

public sealed record WarehouseReceiptUnitResponse(
    long RecepcionMercanciaUnidadId,int NumeroLinea,string CodigoArticulo,string Descripcion,int NumeroUnidad,
    string? Serial,string? Motor,string? Chasis,string? Vin,string? Color,string? Modelo,
    string? EstadoFisico,string? Observacion,string? RevisadoPor,DateTime? RevisadoEnUtc);

public sealed record WarehouseReceiptDetailResponse(
    WarehouseReceiptListItemResponse Recepcion,IReadOnlyList<WarehouseReceiptUnitResponse> Unidades);

public sealed record WarehouseReceiptCheckRequest(long RecepcionMercanciaUnidadId,string EstadoFisico,string? Observacion);
public sealed record SaveWarehouseReceiptChecksRequest(IReadOnlyList<WarehouseReceiptCheckRequest> Revisiones,long? UsuarioId);
public sealed record WarehouseReceiptCheckSummaryResponse(long RecepcionMercanciaId,int Revisadas,int RecibidasConforme,int RecibidasConNovedad,int NoRecibidas);

public sealed record WarehouseReceiptIssueResponse(
    long RecepcionMercanciaRevisionUnidadId,long RecepcionMercanciaId,string RecepcionNumero,long DocumentoProveedorId,
    string TipoDocumento,string NumeroDocumento,string Proveedor,DateOnly FechaDocumento,DateOnly FechaContable,string Bodega,
    long RecepcionMercanciaUnidadId,int NumeroLinea,string CodigoArticulo,string Descripcion,int NumeroUnidad,
    string? Serial,string? Motor,string? Chasis,string? Vin,string? Color,string? Modelo,
    string EstadoFisico,string? Observacion,string RevisadoPor,DateTime RevisadoEnUtc);

public sealed record ResolveWarehouseReceiptIssueRequest(string Resultado,string? ObservacionGestion,long? UsuarioId);
public sealed record ResolvedWarehouseReceiptIssueResponse(
    long RecepcionMercanciaRevisionUnidadId,string Estado,string Resultado,string? ObservacionGestion,string GestionadaPor,DateTime GestionadaEnUtc);

public sealed record PostServiceAccrualRequest(
    long PeriodoContableId,
    string? CuentaImpuestoCodigo,
    string? CuentaRetencionCodigo,
    string CuentaPorPagarCodigo,
    long? UsuarioId,
    Guid? CorrelationId);

public sealed record PostedServiceAccrualResponse(
    long CausacionServicioId,
    long ComprobanteContableId,
    string Estado,
    bool YaExistia);

public sealed record ServiceAccountLineRequest(int NumeroLinea,string CuentaContableCodigo);
public sealed record AssignServiceAccountsRequest(string? CentroCostoCodigo,string? ProyectoCodigo,IReadOnlyList<ServiceAccountLineRequest> Lineas);
public sealed record AssignedServiceAccountsResponse(long CausacionServicioId,string Estado);

public sealed record AccountingPeriodResponse(long PeriodoContableId,string Codigo,DateOnly FechaInicio,DateOnly FechaFin,string Estado);
public sealed record AccountingAccountResponse(long CuentaContableId,string Codigo,string Nombre,string Tipo,string Naturaleza);
public sealed record ServiceAccrualLineResponse(int NumeroLinea,string Descripcion,string? CuentaContableCodigo,decimal Base,decimal Impuestos,decimal Retenciones,decimal Total);
public sealed record AccountingEntryLineResponse(int NumeroLinea,string CuentaCodigo,string CuentaNombre,string Descripcion,decimal Debito,decimal Credito,string? CentroCostoCodigo,string? ProyectoCodigo);
public sealed record ServiceAccrualWorkflowResponse(
    long CausacionServicioId,string Numero,string Estado,DateOnly FechaContable,string DocumentoNumero,string Proveedor,
    string? CentroCostoCodigo,string? ProyectoCodigo,long? PeriodoContableId,long? ComprobanteContableId,
    decimal Base,decimal Impuestos,decimal Retenciones,decimal PorPagar,
    IReadOnlyList<ServiceAccrualLineResponse> Lineas,IReadOnlyList<AccountingEntryLineResponse> ComprobanteLineas);
