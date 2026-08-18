using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;

namespace NexoERP.Api.Inventory;

public sealed class InventoryOperationsRepository(TenantConnectionFactory connections)
{
    public Task<InventoryDocumentOperationResponse> DispatchTransferAsync(long e,long id,PostTransferRequest r,CancellationToken ct)
        => ExecuteOperationAsync(e,"inv.usp_DespacharTraslado","@TrasladoId",id,r.PeriodoInventarioId,r.FechaContable,r.UsuarioId,r.CorrelationId,null,ct);
    public Task<InventoryDocumentOperationResponse> ReceiveTransferAsync(long e,long id,PostTransferRequest r,CancellationToken ct)
        => ExecuteOperationAsync(e,"inv.usp_RecibirTraslado","@TrasladoId",id,r.PeriodoInventarioId,r.FechaContable,r.UsuarioId,r.CorrelationId,r.FechaRecepcion,ct);
    public Task<InventoryDocumentOperationResponse> PostReturnAsync(long e,long id,PostDocumentRequest r,CancellationToken ct)
        => ExecuteSimpleAsync(e,"inv.usp_ContabilizarDevolucionProveedor","@DevolucionProveedorId",id,r.UsuarioId,r.CorrelationId,ct);
    public Task<InventoryDocumentOperationResponse> PostSalesReturnAsync(long e,long id,PostDocumentRequest r,CancellationToken ct)
        => ExecuteSimpleAsync(e,"inv.usp_ContabilizarDevolucionVenta","@DevolucionVentaId",id,r.UsuarioId,r.CorrelationId,ct);
    public Task<InventoryDocumentOperationResponse> ApplyCountAsync(long e,long id,ApplyInventoryDocumentRequest r,CancellationToken ct)
        => ExecuteOperationAsync(e,"inv.usp_AplicarConteoFisico","@ConteoFisicoId",id,r.PeriodoInventarioId,r.FechaContable,r.UsuarioId,r.CorrelationId,null,ct);
    public Task<InventoryDocumentOperationResponse> ApplyLandedCostAsync(long e,long id,ApplyInventoryDocumentRequest r,CancellationToken ct)
        => ExecuteOperationAsync(e,"cost.usp_AplicarDistribucionCosto","@DistribucionCostoId",id,r.PeriodoInventarioId,r.FechaContable,r.UsuarioId,r.CorrelationId,null,ct);

    public async Task<CreatedInventoryDocumentResponse> CreateTransferAsync(long e,CreateTransferRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);await using var transaction=await connection.BeginTransactionAsync(ct);var tx=(SqlTransaction)transaction;
        var existing=await FindDocumentAsync(connection,tx,"inv.Traslado","TrasladoId",e,r.Numero,ct);if(existing is not null){await transaction.RollbackAsync(ct);return new(existing.Value,r.Numero,"BORRADOR",true);}
        await using var header=connection.CreateCommand();header.Transaction=tx;header.CommandText="INSERT inv.Traslado(EmpresaId,TrasladoGuid,Numero,BodegaOrigenId,BodegaTransitoId,BodegaDestinoId,FechaSalida,CreadoPorUsuarioId) OUTPUT inserted.TrasladoId VALUES(@E,@G,@N,@O,@T,@D,@F,@U);";Add(header,"@E",SqlDbType.BigInt,e);Add(header,"@G",SqlDbType.UniqueIdentifier,r.TrasladoGuid??Guid.NewGuid());Add(header,"@N",SqlDbType.NVarChar,r.Numero.Trim(),50);Add(header,"@O",SqlDbType.BigInt,r.BodegaOrigenId);Add(header,"@T",SqlDbType.BigInt,r.BodegaTransitoId);Add(header,"@D",SqlDbType.BigInt,r.BodegaDestinoId);Add(header,"@F",SqlDbType.DateTime2,r.FechaSalida);Add(header,"@U",SqlDbType.BigInt,r.UsuarioId);var id=Convert.ToInt64(await header.ExecuteScalarAsync(ct));
        for(var i=0;i<r.Lineas.Count;i++){var line=r.Lineas[i];await using var command=connection.CreateCommand();command.Transaction=tx;command.CommandText="INSERT inv.TrasladoLinea(EmpresaId,TrasladoId,NumeroLinea,ArticuloId,CantidadDespachada,LoteId) OUTPUT inserted.TrasladoLineaId VALUES(@E,@H,@L,@A,@Q,@Lot);";Add(command,"@E",SqlDbType.BigInt,e);Add(command,"@H",SqlDbType.BigInt,id);Add(command,"@L",SqlDbType.Int,i+1);Add(command,"@A",SqlDbType.BigInt,line.ArticuloId);AddDecimal(command,"@Q",line.Cantidad,20,6);Add(command,"@Lot",SqlDbType.BigInt,line.LoteId);var lineId=Convert.ToInt64(await command.ExecuteScalarAsync(ct));await LinkUnitsAsync(connection,tx,"inv.TrasladoLineaUnidad","TrasladoLineaId",e,lineId,line.UnidadSerializadaIds,ct);}
        await transaction.CommitAsync(ct);return new(id,r.Numero,"BORRADOR",false);
    }

    public async Task<CreatedInventoryDocumentResponse> CreateSupplierReturnAsync(long e,CreateSupplierReturnRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);await using var transaction=await connection.BeginTransactionAsync(ct);var tx=(SqlTransaction)transaction;var existing=await FindDocumentAsync(connection,tx,"inv.DevolucionProveedor","DevolucionProveedorId",e,r.Numero,ct);if(existing is not null){await transaction.RollbackAsync(ct);return new(existing.Value,r.Numero,"VALIDADA",true);}
        await using var header=connection.CreateCommand();header.Transaction=tx;header.CommandText="INSERT inv.DevolucionProveedor(EmpresaId,DevolucionGuid,Numero,TerceroId,BodegaId,PeriodoInventarioId,FechaMovimiento,FechaContable,Motivo,Estado,CreadoPorUsuarioId) OUTPUT inserted.DevolucionProveedorId VALUES(@E,@G,@N,@T,@B,@P,@F,@C,@M,'VALIDADA',@U);";Add(header,"@E",SqlDbType.BigInt,e);Add(header,"@G",SqlDbType.UniqueIdentifier,r.DevolucionGuid??Guid.NewGuid());Add(header,"@N",SqlDbType.NVarChar,r.Numero.Trim(),50);Add(header,"@T",SqlDbType.BigInt,r.TerceroId);Add(header,"@B",SqlDbType.BigInt,r.BodegaId);Add(header,"@P",SqlDbType.BigInt,r.PeriodoInventarioId);Add(header,"@F",SqlDbType.DateTime2,r.FechaMovimiento);Add(header,"@C",SqlDbType.Date,r.FechaContable.ToDateTime(TimeOnly.MinValue));Add(header,"@M",SqlDbType.NVarChar,r.Motivo.Trim(),500);Add(header,"@U",SqlDbType.BigInt,r.UsuarioId);var id=Convert.ToInt64(await header.ExecuteScalarAsync(ct));
        for(var i=0;i<r.Lineas.Count;i++){var line=r.Lineas[i];await using var command=connection.CreateCommand();command.Transaction=tx;command.CommandText="INSERT inv.DevolucionProveedorLinea(EmpresaId,DevolucionProveedorId,NumeroLinea,RecepcionMercanciaLineaId,ArticuloId,CantidadBase,UbicacionId,LoteId) OUTPUT inserted.DevolucionProveedorLineaId VALUES(@E,@H,@L,@R,@A,@Q,@U,@Lot);";Add(command,"@E",SqlDbType.BigInt,e);Add(command,"@H",SqlDbType.BigInt,id);Add(command,"@L",SqlDbType.Int,i+1);Add(command,"@R",SqlDbType.BigInt,line.RecepcionMercanciaLineaId);Add(command,"@A",SqlDbType.BigInt,line.ArticuloId);AddDecimal(command,"@Q",line.CantidadBase,20,6);Add(command,"@U",SqlDbType.BigInt,line.UbicacionId);Add(command,"@Lot",SqlDbType.BigInt,line.LoteId);var lineId=Convert.ToInt64(await command.ExecuteScalarAsync(ct));await LinkUnitsAsync(connection,tx,"inv.DevolucionProveedorLineaUnidad","DevolucionProveedorLineaId",e,lineId,line.UnidadSerializadaIds,ct);}
        await transaction.CommitAsync(ct);return new(id,r.Numero,"VALIDADA",false);
    }

    public async Task<CreatedInventoryDocumentResponse> CreateSalesReturnAsync(long e,CreateSalesReturnRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);await using var transaction=await connection.BeginTransactionAsync(ct);var tx=(SqlTransaction)transaction;var existing=await FindDocumentAsync(connection,tx,"inv.DevolucionVenta","DevolucionVentaId",e,r.Numero,ct);if(existing is not null){await transaction.RollbackAsync(ct);return new(existing.Value,r.Numero,"VALIDADA",true);}
        await using var header=connection.CreateCommand();header.Transaction=tx;header.CommandText="INSERT inv.DevolucionVenta(EmpresaId,DevolucionGuid,Numero,TerceroId,BodegaId,PeriodoInventarioId,FechaMovimiento,FechaContable,Motivo,Estado,CreadoPorUsuarioId) OUTPUT inserted.DevolucionVentaId VALUES(@E,@G,@N,@T,@B,@P,@F,@C,@M,'VALIDADA',@U);";Add(header,"@E",SqlDbType.BigInt,e);Add(header,"@G",SqlDbType.UniqueIdentifier,r.DevolucionGuid??Guid.NewGuid());Add(header,"@N",SqlDbType.NVarChar,r.Numero.Trim(),50);Add(header,"@T",SqlDbType.BigInt,r.TerceroId);Add(header,"@B",SqlDbType.BigInt,r.BodegaId);Add(header,"@P",SqlDbType.BigInt,r.PeriodoInventarioId);Add(header,"@F",SqlDbType.DateTime2,r.FechaMovimiento);Add(header,"@C",SqlDbType.Date,r.FechaContable.ToDateTime(TimeOnly.MinValue));Add(header,"@M",SqlDbType.NVarChar,r.Motivo.Trim(),500);Add(header,"@U",SqlDbType.BigInt,r.UsuarioId);var id=Convert.ToInt64(await header.ExecuteScalarAsync(ct));
        for(var i=0;i<r.Lineas.Count;i++){var line=r.Lineas[i];await using var command=connection.CreateCommand();command.Transaction=tx;command.CommandText="INSERT inv.DevolucionVentaLinea(EmpresaId,DevolucionVentaId,NumeroLinea,MovimientoSalidaOriginalId,ArticuloId,CantidadBase,UbicacionId,LoteId) OUTPUT inserted.DevolucionVentaLineaId VALUES(@E,@H,@L,@R,@A,@Q,@U,@Lot);";Add(command,"@E",SqlDbType.BigInt,e);Add(command,"@H",SqlDbType.BigInt,id);Add(command,"@L",SqlDbType.Int,i+1);Add(command,"@R",SqlDbType.BigInt,line.MovimientoSalidaOriginalId);Add(command,"@A",SqlDbType.BigInt,line.ArticuloId);AddDecimal(command,"@Q",line.CantidadBase,20,6);Add(command,"@U",SqlDbType.BigInt,line.UbicacionId);Add(command,"@Lot",SqlDbType.BigInt,line.LoteId);var lineId=Convert.ToInt64(await command.ExecuteScalarAsync(ct));await LinkUnitsAsync(connection,tx,"inv.DevolucionVentaLineaUnidad","DevolucionVentaLineaId",e,lineId,line.UnidadSerializadaIds,ct);}
        await transaction.CommitAsync(ct);return new(id,r.Numero,"VALIDADA",false);
    }

    public async Task<ReconcileInventoryResponse> ReconcileAsync(long e,ReconcileInventoryRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct); await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_ReconciliarInventario";
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,"@BodegaId",SqlDbType.BigInt,r.BodegaId); Add(command,"@ArticuloId",SqlDbType.BigInt,r.ArticuloId); Add(command,"@UsuarioId",SqlDbType.BigInt,r.UsuarioId);
        await using var reader=await command.ExecuteReaderAsync(ct); if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La reconciliacion no devolvio resultado.");
        return new(reader.GetInt64(0),reader.GetString(1),reader.GetInt32(2));
    }

    public async Task<IReadOnlyList<SupplierReturnSourceResponse>> GetSupplierReturnSourcesAsync(long e,string? q,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);await using var command=connection.CreateCommand();command.CommandText="""
            SELECT l.RecepcionMercanciaLineaId,r.Numero,t.RazonSocial,r.TerceroId,r.BodegaId,b.Nombre,l.ArticuloId,a.Codigo,a.Descripcion,l.LoteId,l.CantidadBase,l.CantidadBase-ISNULL(d.Devuelta,0),CASE WHEN l.CantidadBase=0 THEN 0 ELSE l.CostoTotalCapitalizable/l.CantidadBase END
            FROM inv.RecepcionMercanciaLinea l JOIN inv.RecepcionMercancia r ON r.EmpresaId=l.EmpresaId AND r.RecepcionMercanciaId=l.RecepcionMercanciaId JOIN ter.Tercero t ON t.EmpresaId=r.EmpresaId AND t.TerceroId=r.TerceroId JOIN inv.Bodega b ON b.EmpresaId=r.EmpresaId AND b.BodegaId=r.BodegaId JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
            OUTER APPLY(SELECT SUM(dl.CantidadBase) Devuelta FROM inv.DevolucionProveedorLinea dl JOIN inv.DevolucionProveedor dh ON dh.EmpresaId=dl.EmpresaId AND dh.DevolucionProveedorId=dl.DevolucionProveedorId WHERE dl.EmpresaId=l.EmpresaId AND dl.RecepcionMercanciaLineaId=l.RecepcionMercanciaLineaId AND dh.Estado NOT IN('CANCELADA','REVERTIDA'))d
            WHERE l.EmpresaId=@E AND r.Estado='CONTABILIZADA' AND l.CantidadBase-ISNULL(d.Devuelta,0)>0 AND (@Q IS NULL OR r.Numero LIKE '%'+@Q+'%' OR t.RazonSocial LIKE '%'+@Q+'%' OR a.Codigo LIKE '%'+@Q+'%' OR a.Descripcion LIKE '%'+@Q+'%') ORDER BY r.FechaContable DESC,r.Numero,l.NumeroLinea;
            """;Add(command,"@E",SqlDbType.BigInt,e);Add(command,"@Q",SqlDbType.NVarChar,string.IsNullOrWhiteSpace(q)?null:q.Trim(),120);await using var reader=await command.ExecuteReaderAsync(ct);var result=new List<SupplierReturnSourceResponse>();while(await reader.ReadAsync(ct))result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.GetString(2),reader.GetInt64(3),reader.GetInt64(4),reader.GetString(5),reader.GetInt64(6),reader.GetString(7),reader.GetString(8),reader.IsDBNull(9)?null:reader.GetInt64(9),reader.GetDecimal(10),reader.GetDecimal(11),reader.GetDecimal(12)));return result;
    }

    public async Task<IReadOnlyList<SalesReturnSourceResponse>> GetSalesReturnSourcesAsync(long e,string? q,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);await using var command=connection.CreateCommand();command.CommandText="""
            SELECT m.MovimientoInventarioId,m.NumeroDocumento,m.TerceroId,m.BodegaId,b.Nombre,m.ArticuloId,a.Codigo,a.Descripcion,m.LoteId,m.CantidadSalida,m.CantidadSalida-ISNULL(d.Devuelta,0),m.CostoUnitarioMovimiento
            FROM inv.MovimientoInventario m JOIN inv.Bodega b ON b.EmpresaId=m.EmpresaId AND b.BodegaId=m.BodegaId JOIN inv.Articulo a ON a.EmpresaId=m.EmpresaId AND a.ArticuloId=m.ArticuloId
            OUTER APPLY(SELECT SUM(dl.CantidadBase) Devuelta FROM inv.DevolucionVentaLinea dl JOIN inv.DevolucionVenta dh ON dh.EmpresaId=dl.EmpresaId AND dh.DevolucionVentaId=dl.DevolucionVentaId WHERE dl.EmpresaId=m.EmpresaId AND dl.MovimientoSalidaOriginalId=m.MovimientoInventarioId AND dh.Estado NOT IN('CANCELADA','REVERTIDA'))d
            WHERE m.EmpresaId=@E AND m.ModuloOrigen='VENTAS' AND m.CantidadSalida>0 AND m.CantidadSalida-ISNULL(d.Devuelta,0)>0 AND (@Q IS NULL OR m.NumeroDocumento LIKE '%'+@Q+'%' OR a.Codigo LIKE '%'+@Q+'%' OR a.Descripcion LIKE '%'+@Q+'%') ORDER BY m.FechaContable DESC,m.MovimientoInventarioId DESC;
            """;Add(command,"@E",SqlDbType.BigInt,e);Add(command,"@Q",SqlDbType.NVarChar,string.IsNullOrWhiteSpace(q)?null:q.Trim(),120);await using var reader=await command.ExecuteReaderAsync(ct);var result=new List<SalesReturnSourceResponse>();while(await reader.ReadAsync(ct))result.Add(new(reader.GetInt64(0),reader.GetString(1),reader.IsDBNull(2)?null:reader.GetInt64(2),reader.GetInt64(3),reader.GetString(4),reader.GetInt64(5),reader.GetString(6),reader.GetString(7),reader.IsDBNull(8)?null:reader.GetInt64(8),reader.GetDecimal(9),reader.GetDecimal(10),reader.GetDecimal(11)));return result;
    }

    public async Task<ImpairmentResponse> RegisterImpairmentAsync(long e,ImpairmentRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct); await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_RegistrarDeterioroInventario";
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,"@BodegaId",SqlDbType.BigInt,r.BodegaId); Add(command,"@ArticuloId",SqlDbType.BigInt,r.ArticuloId);
        Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,r.PeriodoInventarioId); Add(command,"@Tipo",SqlDbType.VarChar,r.Tipo,20); AddDecimal(command,"@ValorNetoRealizable",r.ValorNetoRealizable,20,4);
        Add(command,"@Motivo",SqlDbType.NVarChar,r.Motivo,500); Add(command,"@DocumentoSoporte",SqlDbType.NVarChar,r.DocumentoSoporte,100); Add(command,"@UsuarioId",SqlDbType.BigInt,r.UsuarioId); Add(command,"@DeterioroRelacionadoId",SqlDbType.BigInt,r.DeterioroRelacionadoId);
        await using var reader=await command.ExecuteReaderAsync(ct); if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("El deterioro no devolvio resultado.");
        return new(reader.GetInt64(0),reader.GetDecimal(1),reader.GetDecimal(2),reader.GetDecimal(3),reader.GetDecimal(4));
    }

    public async Task<NegativeInventoryResponse> RegisterNegativeAsync(long e,RegisterNegativeInventoryRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct); await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_RegistrarSalidaExcepcionalNegativa";
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,"@BodegaId",SqlDbType.BigInt,r.BodegaId); Add(command,"@ArticuloId",SqlDbType.BigInt,r.ArticuloId); Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,r.PeriodoInventarioId);
        Add(command,"@FechaMovimiento",SqlDbType.DateTime2,r.FechaMovimiento); Add(command,"@FechaContable",SqlDbType.Date,r.FechaContable.ToDateTime(TimeOnly.MinValue)); Add(command,"@TipoDocumentoOrigen",SqlDbType.VarChar,r.TipoDocumentoOrigen,40);
        Add(command,"@DocumentoOrigenId",SqlDbType.BigInt,r.DocumentoOrigenId); Add(command,"@NumeroDocumento",SqlDbType.NVarChar,r.NumeroDocumento,50); AddDecimal(command,"@CantidadSolicitada",r.CantidadSolicitada,20,6);
        Add(command,"@Motivo",SqlDbType.NVarChar,r.Motivo,500); Add(command,"@AutorizadoPorUsuarioId",SqlDbType.BigInt,r.UsuarioId); Add(command,"@IdempotencyKey",SqlDbType.UniqueIdentifier,r.IdempotencyKey); Add(command,"@CorrelationId",SqlDbType.UniqueIdentifier,r.CorrelationId);
        await using var reader=await command.ExecuteReaderAsync(ct); if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La salida excepcional no devolvio resultado.");
        return new(reader.GetInt64(0),reader.GetString(1),reader.GetDecimal(2),reader.GetDecimal(3),reader.GetBoolean(4));
    }

    public async Task<NegativeInventoryResponse> RegularizeNegativeAsync(long e,long id,RegularizeNegativeInventoryRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct); await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_RegularizarSalidaExcepcionalNegativa";
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,"@SalidaExcepcionalNegativaId",SqlDbType.BigInt,id); Add(command,"@RecepcionMercanciaLineaId",SqlDbType.BigInt,r.RecepcionMercanciaLineaId);
        Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,r.PeriodoInventarioId); Add(command,"@FechaContable",SqlDbType.Date,r.FechaContable.ToDateTime(TimeOnly.MinValue)); Add(command,"@UsuarioId",SqlDbType.BigInt,r.UsuarioId); Add(command,"@CorrelationId",SqlDbType.UniqueIdentifier,r.CorrelationId);
        await using var reader=await command.ExecuteReaderAsync(ct); if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La regularizacion no devolvio resultado.");
        return new(reader.GetInt64(0),reader.GetString(1),null,null,reader.GetBoolean(2));
    }

    public async Task<ReverseInventoryMovementResponse> ReverseMovementAsync(long e,long id,ReverseInventoryMovementRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct); await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_ReversarMovimientoInventario";
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,"@MovimientoOriginalId",SqlDbType.BigInt,id); Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,r.PeriodoInventarioId);
        Add(command,"@FechaContable",SqlDbType.Date,r.FechaContable.ToDateTime(TimeOnly.MinValue)); Add(command,"@Motivo",SqlDbType.NVarChar,r.Motivo,500); Add(command,"@IdempotencyKey",SqlDbType.UniqueIdentifier,r.IdempotencyKey);
        Add(command,"@UsuarioId",SqlDbType.BigInt,r.UsuarioId); Add(command,"@AprobacionOperacionId",SqlDbType.BigInt,r.AprobacionOperacionId); Add(command,"@CorrelationId",SqlDbType.UniqueIdentifier,r.CorrelationId);
        await using var reader=await command.ExecuteReaderAsync(ct); if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La reversa no devolvio resultado.");
        return new(reader.GetInt64(0),reader.GetInt64(1),reader.GetBoolean(2));
    }

    public async Task<InventoryPeriodResponse> ClosePeriodAsync(long e,long id,CloseInventoryPeriodRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);
        await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_CerrarPeriodoInventario";
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,id); Add(command,"@UsuarioId",SqlDbType.BigInt,r.UsuarioId);
        await using var reader=await command.ExecuteReaderAsync(ct);
        if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("El cierre no devolvió resultado.");
        return new(reader.GetInt64(0),reader.GetString(1),reader.GetInt32(2),reader.GetBoolean(3));
    }

    public async Task<InventoryPeriodResponse> ReopenPeriodAsync(long e,long id,ReopenInventoryPeriodRequest r,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);
        await using var command=connection.CreateCommand();
        command.CommandType=CommandType.StoredProcedure; command.CommandText="inv.usp_ReabrirPeriodoInventario";
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,id); Add(command,"@Motivo",SqlDbType.NVarChar,r.Motivo,500); Add(command,"@UsuarioId",SqlDbType.BigInt,r.UsuarioId);
        await using var reader=await command.ExecuteReaderAsync(ct);
        if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La reapertura no devolvió resultado.");
        return new(reader.GetInt64(0),reader.GetString(1),null,null);
    }

    private async Task<InventoryDocumentOperationResponse> ExecuteSimpleAsync(long e,string procedure,string idName,long id,long? user,Guid? correlation,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);
        await using var command=connection.CreateCommand(); command.CommandType=CommandType.StoredProcedure; command.CommandText=procedure;
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,idName,SqlDbType.BigInt,id); Add(command,"@UsuarioId",SqlDbType.BigInt,user); Add(command,"@CorrelationId",SqlDbType.UniqueIdentifier,correlation);
        return await ReadOperationAsync(command,ct);
    }

    private async Task<InventoryDocumentOperationResponse> ExecuteOperationAsync(long e,string procedure,string idName,long id,long period,DateOnly date,long? user,Guid? correlation,DateTime? reception,CancellationToken ct)
    {
        await using var connection=await connections.OpenAsync(e,false,ct);
        await using var command=connection.CreateCommand(); command.CommandType=CommandType.StoredProcedure; command.CommandText=procedure;
        Add(command,"@EmpresaId",SqlDbType.BigInt,e); Add(command,idName,SqlDbType.BigInt,id); Add(command,"@PeriodoInventarioId",SqlDbType.BigInt,period);
        Add(command,"@FechaContable",SqlDbType.Date,date.ToDateTime(TimeOnly.MinValue));
        if(procedure=="inv.usp_RecibirTraslado") Add(command,"@FechaRecepcion",SqlDbType.DateTime2,reception);
        Add(command,"@UsuarioId",SqlDbType.BigInt,user); Add(command,"@CorrelationId",SqlDbType.UniqueIdentifier,correlation);
        return await ReadOperationAsync(command,ct);
    }

    private static async Task<InventoryDocumentOperationResponse> ReadOperationAsync(SqlCommand command,CancellationToken ct)
    {
        await using var reader=await command.ExecuteReaderAsync(ct);
        if(!await reader.ReadAsync(ct)) throw new InvalidOperationException("La operación de inventario no devolvió resultado.");
        return new(reader.GetInt64(0),reader.GetString(1),reader.GetInt32(2),reader.GetBoolean(3));
    }
    private static async Task<long?> FindDocumentAsync(SqlConnection connection,SqlTransaction transaction,string table,string idColumn,long e,string number,CancellationToken ct){await using var command=connection.CreateCommand();command.Transaction=transaction;command.CommandText=$"SELECT {idColumn} FROM {table} WHERE EmpresaId=@E AND Numero=@N;";Add(command,"@E",SqlDbType.BigInt,e);Add(command,"@N",SqlDbType.NVarChar,number.Trim(),50);var value=await command.ExecuteScalarAsync(ct);return value is null or DBNull?null:Convert.ToInt64(value);}
    private static async Task LinkUnitsAsync(SqlConnection connection,SqlTransaction transaction,string table,string lineColumn,long e,long lineId,IReadOnlyList<long>? units,CancellationToken ct){if(units is null)return;foreach(var unit in units.Distinct()){await using var command=connection.CreateCommand();command.Transaction=transaction;command.CommandText=$"INSERT {table}(EmpresaId,{lineColumn},UnidadSerializadaId) VALUES(@E,@L,@U);";Add(command,"@E",SqlDbType.BigInt,e);Add(command,"@L",SqlDbType.BigInt,lineId);Add(command,"@U",SqlDbType.BigInt,unit);await command.ExecuteNonQueryAsync(ct);}}
    private static void Add(SqlCommand c,string n,SqlDbType t,object? v,int size=0){var p=size==0?new SqlParameter(n,t):new SqlParameter(n,t,size);p.Value=v??DBNull.Value;c.Parameters.Add(p);}
    private static void AddDecimal(SqlCommand c,string n,decimal v,byte precision,byte scale)=>c.Parameters.Add(new SqlParameter(n,SqlDbType.Decimal){Precision=precision,Scale=scale,Value=v});
}
