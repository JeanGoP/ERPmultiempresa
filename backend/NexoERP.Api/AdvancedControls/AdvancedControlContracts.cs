namespace NexoERP.Api.AdvancedControls;

public sealed record CostConceptResponse(long ConceptoCostoId,string Codigo,string Nombre,string Tratamiento,string? MetodoDistribucionDefecto,bool RequiereDocumentoSoporte);
public sealed record LandedCostSourceResponse(long RecepcionMercanciaLineaId,string Recepcion,string Proveedor,long TerceroId,DateOnly FechaContable,long ArticuloId,string Codigo,string Descripcion,decimal CantidadBase,decimal CostoCapitalizable,decimal CostoAdicional);
public sealed record CreateLandedCostLineRequest(long RecepcionMercanciaLineaId,decimal? BaseManual,decimal? PorcentajeManual,decimal? ValorManual);
public sealed record CreateLandedCostRequest(long ConceptoCostoId,long TerceroId,string NumeroSoporte,DateOnly FechaDocumento,string Moneda,decimal ValorDistribuible,string Metodo,long? UsuarioId,IReadOnlyList<CreateLandedCostLineRequest> Lineas);
public sealed record CreatedLandedCostResponse(long DocumentoCostoId,long DistribucionCostoId,string Estado,bool YaExistia);
public sealed record LandedCostListResponse(long DistribucionCostoId,string NumeroSoporte,string Concepto,string Proveedor,DateOnly FechaDocumento,string Metodo,decimal ValorTotal,string Estado,int Lineas,DateTime? AplicadaEnUtc);

public sealed record CostBookResponse(long LibroCostoId,string Codigo,string Nombre,string Categoria,string FormulaValoracion,bool EsPrincipal,string Estado);
public sealed record CreateCostBookRequest(string Codigo,string Nombre,string Categoria,string FormulaValoracion,bool EsPrincipal);
public sealed record CostPolicyResponse(long PoliticaValoracionGrupoId,long LibroCostoId,string Libro,long GrupoInventarioId,string Grupo,string FormulaValoracion,DateOnly VigenteDesde,DateOnly? VigenteHasta,string? MotivoCambio);
public sealed record SaveCostPolicyRequest(long LibroCostoId,long GrupoInventarioId,string FormulaValoracion,DateOnly VigenteDesde,DateOnly? VigenteHasta,string? MotivoCambio,long? UsuarioId);
public sealed record InventoryGroupResponse(long GrupoInventarioId,string Codigo,string Nombre,string NaturalezaUso);
public sealed record CreateInventoryGroupRequest(string Codigo,string Nombre,string NaturalezaUso);
public sealed record CostBookBalanceResponse(long LibroCostoId,string Libro,long BodegaId,string Bodega,long ArticuloId,string Codigo,string Descripcion,decimal Existencia,decimal CostoUnitario,decimal ValorTotal);

public sealed record InventoryNetValueResponse(long BodegaId,string Bodega,long ArticuloId,string Codigo,string Descripcion,decimal Existencia,decimal CostoHistorico,decimal DeterioroAcumulado,decimal ValorNetoContable);
public sealed record ImpairmentListResponse(long DeterioroInventarioId,DateTime Fecha,string Tipo,string Bodega,string Codigo,string Descripcion,decimal CostoHistorico,decimal ValorDeterioro,decimal SaldoPosterior,decimal ValorNetoContable,string Motivo,string? DocumentoSoporte);
public sealed record NegativeExceptionListResponse(long SalidaExcepcionalNegativaId,string NumeroDocumento,string Bodega,string Codigo,string Descripcion,decimal CantidadSolicitada,decimal CantidadValorizada,decimal CantidadPendiente,string Estado,string Motivo,DateTime CreadoEnUtc);
public sealed record NegativeRegularizationSourceResponse(long RecepcionMercanciaLineaId,string Recepcion,long BodegaId,long ArticuloId,string Codigo,string Descripcion,decimal CantidadDisponible,decimal CostoUnitario);

public sealed record CreatePhysicalCountRequest(string Numero,long BodegaId,DateTime FechaCorte,long? UsuarioId);
public sealed record PhysicalCountListResponse(long ConteoFisicoId,string Numero,long BodegaId,string Bodega,DateTime FechaCorte,string Estado,int Lineas,int Capturas,decimal DiferenciaAbsoluta);
public sealed record PhysicalCountLineResponse(long ConteoFisicoLineaId,long ArticuloId,string Codigo,string Descripcion,string? Ubicacion,string? Lote,decimal ExistenciaTeorica,short? UltimoConteo,decimal? CantidadContada,decimal? CantidadAprobada,decimal? DiferenciaAprobada);
public sealed record CountStateResponse(long ConteoFisicoId,string Estado,bool? YaExistia);
public sealed record CaptureCountRequest(short NumeroConteo,decimal CantidadContada,long? UsuarioId);
public sealed record CountApprovalLineRequest(long ConteoFisicoLineaId,decimal CantidadAprobada);
public sealed record ApprovePhysicalCountRequest(IReadOnlyList<CountApprovalLineRequest> Lineas,long? UsuarioId);

public sealed record AdvancedInventoryPeriodResponse(long PeriodoInventarioId,string Codigo,DateOnly FechaInicio,DateOnly FechaFin,string Estado,DateTime? CerradoEnUtc,int? VersionCierre);
public sealed record ReconciliationListResponse(long ReconciliacionInventarioId,string Estado,int Diferencias,string? Bodega,string? Articulo,DateTime FinalizadaEnUtc);
public sealed record ReversibleMovementResponse(long MovimientoInventarioId,DateOnly FechaContable,string TipoMovimiento,string NumeroDocumento,string Bodega,string Codigo,string Descripcion,decimal Entrada,decimal Salida,decimal ValorMovimiento,bool Reversado);
public sealed record AuditEventResponse(long EventoAuditoriaId,DateTime FechaEnUtc,string Operacion,string Entidad,string? EntidadId,string? DocumentoNumero,string? Usuario,string? Motivo);
