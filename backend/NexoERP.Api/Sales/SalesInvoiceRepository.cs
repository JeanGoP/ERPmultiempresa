using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Data;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Sales;

public sealed record SaleItem(long ArticuloId,long BodegaId,decimal Cantidad,decimal PrecioUnitarioConIva,long[]? UnidadesSerializadas);
public sealed record SaleAdvance(long ReciboCajaId,decimal Valor);
public sealed record SaleConceptLine(long ConceptoVentaId,decimal Valor,string? CentroCosto);
public sealed record SalesCostCenterCorrection(string CentroCosto);
public sealed record SalesPortfolioClassification(string ClaseCartera);
public sealed record SalesInvoiceInput(Guid OperacionGuid,string Numero,long ClienteId,long SucursalId,
    DateOnly FechaContable,DateOnly Vencimiento,SaleItem[] Lineas,SaleConceptLine[] Conceptos,
    int Cuotas,string FrecuenciaCuotas,SaleAdvance[] Anticipos,long? BodegaCarteraId,string? CentroCostoIngreso,
    string ClaseCartera,string? Observacion,SalesExtraInstallment[]? CuotasExtras);

public sealed class SalesInvoiceRepository(TenantConnectionFactory connections,ZeusTransport zeus)
{
    public async Task ClassifyAsync(long company,long id,string category,long user,CancellationToken ct)
    {
        category=category?.Trim().ToUpperInvariant()??"";
        if(category is not("MOTO" or "OTROS" or "MIXTA"))
            throw new ArgumentException("Selecciona motos, otros artículos o cartera mixta.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(ct);
        await using var q=ZeusRepository.Command(c,"UPDATE ven.FacturaVenta SET ClaseCartera=@Class OUTPUT deleted.ClaseCartera WHERE EmpresaId=@E AND FacturaVentaId=@Id",company,tx);
        ZeusRepository.Add(q,"@Class",category);ZeusRepository.Add(q,"@Id",id);
        var previous=await q.ExecuteScalarAsync(ct) as string;
        if(previous is null)throw new ArgumentException("No se encontró la factura en esta empresa.");
        if(previous.Trim().Equals(category,StringComparison.OrdinalIgnoreCase)){await tx.CommitAsync(ct);return;}
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresAnteriores,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'CLASIFICAR_CARTERA_VENTA','ven.FacturaVenta',CONVERT(varchar(30),@Id),@Before,@Detail,'ERP')";
        ZeusRepository.Add(q,"@User",user);ZeusRepository.Add(q,"@Before",JsonSerializer.Serialize(new{claseCartera=previous.Trim()}));ZeusRepository.Add(q,"@Detail",JsonSerializer.Serialize(new{claseCartera=category}));
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
    }
    public async Task<object> ReceivablesAsync(long company,string? search,string? category,int page,CancellationToken ct)
    {
        search=search?.Trim()??"";category=category?.Trim().ToUpperInvariant()??"";
        if(search.Length>100||category is not("" or "MOTO" or "OTROS" or "MIXTA" or "SIN_CLASIFICAR")||page is <1 or >10000)
            throw new ArgumentException("Revisa la búsqueda, el tipo de cartera y la página solicitada.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT f.FacturaVentaId,f.Numero,t.RazonSocial,t.NumeroIdentificacion,f.ClaseCartera,
                c.NumeroCuota,COALESCE(c.FechaVencimiento,f.Vencimiento),
                COALESCE(c.ValorOriginal,f.Total),COALESCE(c.SaldoPendiente,f.SaldoPendiente),f.ZeusEstado
            FROM ven.FacturaVenta f
            JOIN ter.Tercero t ON t.EmpresaId=f.EmpresaId AND t.TerceroId=f.ClienteId
            LEFT JOIN ven.FacturaVentaCuota c ON c.EmpresaId=f.EmpresaId AND c.FacturaVentaId=f.FacturaVentaId
            WHERE f.EmpresaId=@E AND f.SaldoPendiente>0 AND (c.FacturaVentaCuotaId IS NULL OR c.SaldoPendiente>0)
                AND (@Category='' OR f.ClaseCartera=@Category)
                AND (@Q='' OR f.Numero LIKE '%'+@Q+'%' OR t.RazonSocial LIKE '%'+@Q+'%' OR t.NumeroIdentificacion LIKE '%'+@Q+'%')
            ORDER BY f.FacturaVentaId DESC,c.NumeroCuota
            OFFSET @Offset ROWS FETCH NEXT 50 ROWS ONLY;
            SELECT COUNT_BIG(*),COALESCE(SUM(COALESCE(c.SaldoPendiente,f.SaldoPendiente)),0)
            FROM ven.FacturaVenta f
            JOIN ter.Tercero t ON t.EmpresaId=f.EmpresaId AND t.TerceroId=f.ClienteId
            LEFT JOIN ven.FacturaVentaCuota c ON c.EmpresaId=f.EmpresaId AND c.FacturaVentaId=f.FacturaVentaId
            WHERE f.EmpresaId=@E AND f.SaldoPendiente>0 AND (c.FacturaVentaCuotaId IS NULL OR c.SaldoPendiente>0)
                AND (@Category='' OR f.ClaseCartera=@Category)
                AND (@Q='' OR f.Numero LIKE '%'+@Q+'%' OR t.RazonSocial LIKE '%'+@Q+'%' OR t.NumeroIdentificacion LIKE '%'+@Q+'%');
            """,company);
        q.Parameters.Add("@Q",SqlDbType.NVarChar,100).Value=search;
        q.Parameters.Add("@Category",SqlDbType.VarChar,20).Value=category;
        q.Parameters.Add("@Offset",SqlDbType.Int).Value=checked((page-1)*50);
        var items=new List<object>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))items.Add(new{id=r.GetInt64(0),numero=r.GetString(1),cliente=r.GetString(2),identificacion=r.GetString(3),claseCartera=r.GetString(4),
            numeroCuota=r.IsDBNull(5)?(int?)null:r.GetInt32(5),vence=r.GetDateTime(6).ToString("yyyy-MM-dd"),original=r.GetDecimal(7),saldo=r.GetDecimal(8),zeusEstado=r.GetString(9)});
        await r.NextResultAsync(ct);await r.ReadAsync(ct);
        var count=r.GetInt64(0);
        return new{items,pagina=page,totalRegistros=count,totalSaldo=r.GetDecimal(1),paginas=(int)Math.Ceiling(count/50m)};
    }
    public async Task<object> MissingCostCentersAsync(long company,long id,ZeusSettings settings,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"SELECT Snapshot,ZeusEstado FROM ven.FacturaVenta WHERE EmpresaId=@E AND FacturaVentaId=@Id",company);
        ZeusRepository.Add(q,"@Id",id);
        ZeusSnapshot snapshot;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct)||r.GetString(1)!="RECHAZADO"||r.IsDBNull(0))throw new ArgumentException("La factura no está rechazada o no tiene comprobante Zeus pendiente de corrección.");
            snapshot=JsonSerializer.Deserialize<ZeusSnapshot>(r.GetString(0))!;
        }
        if(snapshot.Configuracion.ServidorEsperado!=settings.ServidorEsperado||snapshot.Configuracion.BaseEsperada!=settings.BaseEsperada)
            throw new ArgumentException("El destino Zeus de la factura cambió; revisa la configuración antes de corregirla.");
        var dimensions=await zeus.AccountingDimensionsAsync(company,settings,ct);
        var required=dimensions.CuentasRequierenCentroCosto.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var missing=snapshot.Movimientos.Where(x=>required.Contains(x.Regla.Cuenta)&&string.IsNullOrWhiteSpace(x.Regla.CentroCosto))
            .Select(x=>new{concepto=x.Regla.Concepto,cuenta=x.Regla.Cuenta}).Distinct().ToArray();
        return new{centrosCosto=dimensions.CentrosCosto,faltantes=missing};
    }

    public async Task<int> CorrectCostCentersAsync(long company,long id,string center,long user,ZeusSettings settings,CancellationToken ct)
    {
        center=(center??"").Trim();
        if(center.Length is <1 or >16)throw new ArgumentException("Selecciona un centro de costo de Zeus.");
        var dimensions=await zeus.AccountingDimensionsAsync(company,settings,ct);
        if(!dimensions.CentrosCosto.Any(x=>x.Codigo.Equals(center,StringComparison.OrdinalIgnoreCase)))
            throw new ArgumentException("El centro de costo no existe, está deshabilitado o no es de detalle en Zeus.");
        var required=dimensions.CuentasRequierenCentroCosto.ToHashSet(StringComparer.OrdinalIgnoreCase);
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT Snapshot FROM ven.FacturaVenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND FacturaVentaId=@Id AND ZeusEstado='RECHAZADO'",company,tx);
        ZeusRepository.Add(q,"@Id",id);
        var raw=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("La factura ya no está rechazada; actualiza el seguimiento.");
        var snapshot=JsonSerializer.Deserialize<ZeusSnapshot>(raw)!;
        if(snapshot.Configuracion.ServidorEsperado!=settings.ServidorEsperado||snapshot.Configuracion.BaseEsperada!=settings.BaseEsperada)
            throw new ArgumentException("Cambió el destino Zeus; no se modificó la factura.");
        var fixedMovements=snapshot.Movimientos.Select(x=>required.Contains(x.Regla.Cuenta)&&string.IsNullOrWhiteSpace(x.Regla.CentroCosto)
            ?x with{Regla=x.Regla with{CentroCosto=center}}:x).ToArray();
        var changed=fixedMovements.Where((x,i)=>x!=snapshot.Movimientos[i]).ToArray();
        if(changed.Length==0)throw new ArgumentException("Esta factura no tiene centros de costo obligatorios sin completar.");
        ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(snapshot with{Movimientos=fixedMovements}));
        ZeusRepository.Add(q,"@Center",center);
        ZeusRepository.Add(q,"@GeneralCenter",changed.Any(x=>!x.Regla.Concepto.StartsWith("CONCEPTO_",StringComparison.Ordinal))?center:DBNull.Value);
        ZeusRepository.Add(q,"@User",user);
        q.CommandText="UPDATE ven.FacturaVenta SET Snapshot=@Snapshot,CentroCostoIngresoZeus=COALESCE(CentroCostoIngresoZeus,@GeneralCenter) WHERE EmpresaId=@E AND FacturaVentaId=@Id AND ZeusEstado='RECHAZADO'";
        if(await q.ExecuteNonQueryAsync(ct)!=1)throw new ArgumentException("La factura cambió; actualiza el seguimiento.");
        foreach(var account in changed.Where(x=>x.Regla.Concepto.StartsWith("CONCEPTO_",StringComparison.Ordinal)).Select(x=>x.Regla.Cuenta).Distinct())
        {
            q.Parameters.Add("@Account",SqlDbType.VarChar,16).Value=account;
            q.CommandText="UPDATE ven.FacturaVentaConcepto SET CentroCostoZeus=@Center WHERE EmpresaId=@E AND FacturaVentaId=@Id AND CuentaIngresoZeus=@Account AND CentroCostoZeus IS NULL";
            await q.ExecuteNonQueryAsync(ct);q.Parameters.RemoveAt("@Account");
        }
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'CORREGIR_CENTRO_COSTO_VENTA','ven.FacturaVenta',CONVERT(varchar(30),@Id),@Snapshot,'ERP')";
        await q.ExecuteNonQueryAsync(ct);
        await tx.CommitAsync(ct);
        return changed.Length;
    }

    public async Task<object> ListAsync(long company,string? search,long? before,CancellationToken ct)
    {
        search=search?.Trim()??"";if(search.Length>100)throw new ArgumentException("Búsqueda demasiado larga.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT TOP(51) f.FacturaVentaId,f.Numero,f.FechaContable,t.RazonSocial,f.Total,f.AnticipoAplicado,f.SaldoPendiente,
                f.ZeusEstado,f.ZeusFuente,f.ZeusDocumento,f.ZeusError,f.ClaseCartera
            FROM ven.FacturaVenta f JOIN ter.Tercero t ON t.EmpresaId=f.EmpresaId AND t.TerceroId=f.ClienteId
            WHERE f.EmpresaId=@E AND (@Before IS NULL OR f.FacturaVentaId<@Before)
              AND (@Q='' OR f.Numero LIKE '%'+@Q+'%' OR t.RazonSocial LIKE '%'+@Q+'%'
                   OR t.NumeroIdentificacion LIKE '%'+@Q+'%' OR f.ZeusDocumento LIKE '%'+@Q+'%')
            ORDER BY f.FacturaVentaId DESC;
            """,company);
        q.Parameters.Add("@Q",SqlDbType.NVarChar,100).Value=search;
        q.Parameters.Add("@Before",SqlDbType.BigInt).Value=(object?)before??DBNull.Value;
        var list=new List<object>();long? next=null;await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))
        {
            if(list.Count==50)return new{items=list,siguiente=next};
            next=r.GetInt64(0);list.Add(new{id=next,numero=r.GetString(1),fecha=r.GetDateTime(2).ToString("yyyy-MM-dd"),cliente=r.GetString(3),total=r.GetDecimal(4),anticipo=r.GetDecimal(5),saldo=r.GetDecimal(6),zeusEstado=r.GetString(7),fuente=r.IsDBNull(8)?null:r.GetString(8),documento=r.IsDBNull(9)?null:r.GetString(9),error=r.IsDBNull(10)?null:r.GetString(10),claseCartera=r.GetString(11)});
        }
        return new{items=list,siguiente=(long?)null};
    }
    public async Task<object?> DetailAsync(long company,long id,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT f.Numero,f.FechaContable,f.Vencimiento,f.Cuotas,f.FrecuenciaCuotas,f.Total,
                f.AnticipoAplicado,f.SaldoPendiente,f.ZeusEstado,f.ZeusFuente,f.ZeusDocumento,f.ZeusError,
                t.NumeroIdentificacion,t.RazonSocial,s.Codigo,s.Nombre,f.CentroCostoIngresoZeus,
                f.ClaseCartera,f.Observacion
            FROM ven.FacturaVenta f
            JOIN ter.Tercero t ON t.EmpresaId=f.EmpresaId AND t.TerceroId=f.ClienteId
            JOIN core.Sucursal s ON s.EmpresaId=f.EmpresaId AND s.SucursalId=f.SucursalId
            WHERE f.EmpresaId=@E AND f.FacturaVentaId=@Id;
            SELECT a.Codigo,a.Descripcion,b.Codigo,b.Nombre,l.Cantidad,l.PrecioConIva,l.TarifaIva,l.Base,l.Iva
            FROM ven.FacturaVentaLinea l
            JOIN inv.Articulo a ON a.EmpresaId=l.EmpresaId AND a.ArticuloId=l.ArticuloId
            JOIN inv.Bodega b ON b.EmpresaId=l.EmpresaId AND b.BodegaId=l.BodegaId
            WHERE l.EmpresaId=@E AND l.FacturaVentaId=@Id ORDER BY l.FacturaVentaLineaId;
            SELECT Codigo,Nombre,CuentaIngresoZeus,CentroCostoZeus,Valor
            FROM ven.FacturaVentaConcepto WHERE EmpresaId=@E AND FacturaVentaId=@Id ORDER BY FacturaVentaConceptoId;
            SELECT r.ReciboCajaId,r.FechaContable,r.Concepto,a.Valor
            FROM ven.FacturaAnticipo a JOIN cxc.ReciboCaja r ON r.EmpresaId=a.EmpresaId AND r.ReciboCajaId=a.ReciboCajaId
            WHERE a.EmpresaId=@E AND a.FacturaVentaId=@Id ORDER BY r.FechaContable,r.ReciboCajaId;
            SELECT NumeroCuota,FechaVencimiento,ValorOriginal,SaldoPendiente,TipoCuota
            FROM ven.FacturaVentaCuota WHERE EmpresaId=@E AND FacturaVentaId=@Id ORDER BY NumeroCuota;
            """,company);
        ZeusRepository.Add(q,"@Id",id);
        await using var r=await q.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))return null;
        var header=new{
            id,numero=r.GetString(0),fecha=r.GetDateTime(1).ToString("yyyy-MM-dd"),primerVencimiento=r.GetDateTime(2).ToString("yyyy-MM-dd"),
            cuotas=r.GetInt32(3),frecuencia=r.IsDBNull(4)?null:r.GetString(4),total=r.GetDecimal(5),anticipo=r.GetDecimal(6),saldo=r.GetDecimal(7),
            zeusEstado=r.GetString(8),fuente=r.IsDBNull(9)?null:r.GetString(9),documento=r.IsDBNull(10)?null:r.GetString(10),
            error=r.IsDBNull(11)?null:r.GetString(11),identificacion=r.GetString(12),cliente=r.GetString(13),
            sucursalCodigo=r.GetString(14),sucursal=r.GetString(15),centroCosto=r.IsDBNull(16)?null:r.GetString(16),
            claseCartera=r.GetString(17),observacion=r.IsDBNull(18)?null:r.GetString(18)
        };
        var items=new List<object>();
        await r.NextResultAsync(ct);
        while(await r.ReadAsync(ct))items.Add(new{codigo=r.GetString(0),descripcion=r.GetString(1),bodegaCodigo=r.GetString(2),bodega=r.GetString(3),cantidad=r.GetDecimal(4),precio=r.GetDecimal(5),ivaTarifa=r.GetDecimal(6),@base=r.GetDecimal(7),iva=r.GetDecimal(8)});
        var concepts=new List<object>();
        await r.NextResultAsync(ct);
        while(await r.ReadAsync(ct))concepts.Add(new{codigo=r.GetString(0),nombre=r.GetString(1),cuenta=r.GetString(2),centroCosto=r.IsDBNull(3)?null:r.GetString(3),valor=r.GetDecimal(4)});
        var receipts=new List<object>();
        await r.NextResultAsync(ct);
        while(await r.ReadAsync(ct))receipts.Add(new{reciboId=r.GetInt64(0),fecha=r.GetDateTime(1).ToString("yyyy-MM-dd"),concepto=r.GetString(2),valor=r.GetDecimal(3)});
        var installments=new List<object>();
        await r.NextResultAsync(ct);
        while(await r.ReadAsync(ct))installments.Add(new{numero=r.GetInt32(0),vence=r.GetDateTime(1).ToString("yyyy-MM-dd"),valor=r.GetDecimal(2),saldo=r.GetDecimal(3),tipo=r.GetString(4)});
        return new{header,articulos=items,conceptos=concepts,anticipos=receipts,cuotas=installments};
    }
    public async Task<object> OptionsAsync(long company,long? client,CancellationToken ct)
    {
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var q=ZeusRepository.Command(c,"""
            SELECT SucursalId,Codigo,Nombre FROM core.Sucursal WHERE EmpresaId=@E AND Activa=1 ORDER BY Codigo;
            SELECT t.TerceroId,t.NumeroIdentificacion,t.RazonSocial,p.ZeusEstado FROM ter.Tercero t
            JOIN ven.ClientePerfil p ON p.EmpresaId=t.EmpresaId AND p.TerceroId=t.TerceroId
            WHERE t.EmpresaId=@E AND t.Activo=1 ORDER BY t.RazonSocial;
            SELECT a.ArticuloId,a.Codigo,a.Descripcion,a.Tipo,a.ManejaInventario,a.ManejaSerial,a.PorcentajeIvaVenta,
                b.BodegaId,b.Codigo,b.Nombre,b.SucursalId,ISNULL(s.Existencia,0),s.CostoPromedio
            FROM inv.Articulo a CROSS JOIN inv.Bodega b
            LEFT JOIN inv.SaldoArticuloBodega s ON s.EmpresaId=a.EmpresaId AND s.ArticuloId=a.ArticuloId AND s.BodegaId=b.BodegaId
            WHERE a.EmpresaId=@E AND b.EmpresaId=@E AND a.Activo=1 AND b.Activa=1 AND b.SucursalId IS NOT NULL
            ORDER BY b.Codigo,a.Codigo;
            SELECT u.UnidadSerializadaId,u.ArticuloId,u.BodegaActualId,u.Estado,ui.Tipo,ui.Valor
            FROM inv.UnidadSerializada u LEFT JOIN inv.UnidadIdentificador ui ON ui.EmpresaId=u.EmpresaId AND ui.UnidadSerializadaId=u.UnidadSerializadaId
            WHERE u.EmpresaId=@E AND u.Estado='DISPONIBLE' AND u.BodegaActualId IS NOT NULL;
            SELECT a.ReciboCajaId,a.Saldo,r.Concepto,r.FechaContable,r.ZeusEstado
            FROM cxc.AnticipoCliente a JOIN cxc.ReciboCaja r ON r.EmpresaId=a.EmpresaId AND r.ReciboCajaId=a.ReciboCajaId
            WHERE a.EmpresaId=@E AND a.ClienteId=@C AND a.Saldo>0 ORDER BY r.FechaContable,a.ReciboCajaId;
            SELECT ConceptoVentaId,Codigo,Nombre,CuentaIngresoZeus FROM ven.ConceptoVenta WHERE EmpresaId=@E AND Activo=1 ORDER BY Codigo;
            SELECT b.BodegaId,b.Codigo,b.Nombre,b.SucursalId,z.Configuracion
            FROM inv.Bodega b LEFT JOIN core.ZeusBodegaCuenta z ON z.EmpresaId=b.EmpresaId AND z.BodegaId=b.BodegaId
            WHERE b.EmpresaId=@E AND b.Activa=1 AND b.SucursalId IS NOT NULL ORDER BY b.Codigo;
            """,company);
        q.Parameters.Add("@C",SqlDbType.BigInt).Value=(object?)client??DBNull.Value;
        var branches=new List<object>();var customers=new List<object>();var articles=new List<object>();var serials=new List<object>();var advances=new List<object>();var concepts=new List<object>();var warehouses=new List<object>();
        await using var r=await q.ExecuteReaderAsync(ct);
        while(await r.ReadAsync(ct))branches.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),nombre=r.GetString(2)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))customers.Add(new{id=r.GetInt64(0),identificacion=r.GetString(1),nombre=r.GetString(2),zeusEstado=r.GetString(3)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))articles.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),descripcion=r.GetString(2),tipo=r.GetString(3),inventario=r.GetBoolean(4),serial=r.GetBoolean(5),iva=r.IsDBNull(6)?(decimal?)null:r.GetDecimal(6),bodegaId=r.GetInt64(7),bodegaCodigo=r.GetString(8),bodega=r.GetString(9),sucursalId=r.GetInt64(10),existencia=r.GetDecimal(11),costoPromedio=r.IsDBNull(12)?(decimal?)null:r.GetDecimal(12)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))serials.Add(new{id=r.GetInt64(0),articuloId=r.GetInt64(1),bodegaId=r.GetInt64(2),estado=r.GetString(3),tipo=r.IsDBNull(4)?null:r.GetString(4),valor=r.IsDBNull(5)?null:r.GetString(5)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))advances.Add(new{id=r.GetInt64(0),saldo=r.GetDecimal(1),concepto=r.GetString(2),fecha=r.GetDateTime(3).ToString("yyyy-MM-dd"),zeusEstado=r.GetString(4)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))concepts.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),nombre=r.GetString(2),cuentaIngresoZeus=r.GetString(3)});
        await r.NextResultAsync(ct);while(await r.ReadAsync(ct))
        {
            var account=r.IsDBNull(4)?null:JsonSerializer.Deserialize<ZeusWarehouseAccounts>(r.GetString(4))?.Ingreso;
            warehouses.Add(new{id=r.GetInt64(0),codigo=r.GetString(1),nombre=r.GetString(2),sucursalId=r.GetInt64(3),cuentaIngreso=account});
        }
        return new{sucursales=branches,clientes=customers,articulos=articles,seriales=serials,anticipos=advances,conceptos=concepts,bodegas=warehouses};
    }

    public async Task<object> PostAsync(long company,SalesInvoiceInput input,long user,CancellationToken ct)
    {
        if(input.OperacionGuid==Guid.Empty||input.ClienteId<=0||input.SucursalId<=0||input.FechaContable.Year<2000||input.Vencimiento<input.FechaContable)
            throw new ArgumentException("Selecciona cliente, sucursal, fecha y vencimiento válidos.");
        if(string.IsNullOrWhiteSpace(input.Numero)||input.Numero.Length>15||input.Numero.Any(char.IsControl))
            throw new ArgumentException("Escribe el número de la factura (máximo 15 caracteres admitidos por Zeus).");
        if(input.Lineas is null||input.Lineas.Length>100||input.Cuotas is <1 or >120)
            throw new ArgumentException("La factura admite hasta 100 artículos y entre 1 y 120 cuotas.");
        if(input.FrecuenciaCuotas is not(SalesInstallments.EveryThirtyDays or SalesInstallments.SameDayMonthly))
            throw new ArgumentException("Selecciona la periodicidad de las cuotas.");
        if(input.ClaseCartera is not("MOTO" or "OTROS" or "MIXTA"))
            throw new ArgumentException("Clasifica la cartera como motos, otros artículos o mixta.");
        if(input.Observacion?.Trim().Length>1000)
            throw new ArgumentException("La observación admite máximo 1000 caracteres.");
        var conceptLines=input.Conceptos??[];
        if(conceptLines.Length>100||conceptLines.Any(x=>x.ConceptoVentaId<=0||x.Valor<=0||decimal.Round(x.Valor,2)!=x.Valor||x.CentroCosto?.Trim().Length>16))
            throw new ArgumentException("Revisa los conceptos de venta y sus valores (máximo dos decimales).");
        if(input.CentroCostoIngreso?.Trim().Length>16)throw new ArgumentException("El centro de costo debe tener máximo 16 caracteres.");
        if(input.Lineas.Length==0&&conceptLines.Length==0)throw new ArgumentException("Agrega al menos un artículo o un concepto de venta.");
        var advances=input.Anticipos??[];
        if(advances.Length>100||advances.Any(x=>x.ReciboCajaId<=0||x.Valor<=0||decimal.Round(x.Valor,2)!=x.Valor)
            ||advances.GroupBy(x=>x.ReciboCajaId).Any(g=>g.Count()>1))throw new ArgumentException("Revisa los anticipos seleccionados.");
        foreach(var line in input.Lineas)
            if(line.ArticuloId<=0||line.BodegaId<=0||line.Cantidad<=0||decimal.Round(line.Cantidad,6)!=line.Cantidad
                ||line.PrecioUnitarioConIva<=0||decimal.Round(line.PrecioUnitarioConIva,2)!=line.PrecioUnitarioConIva)
                throw new ArgumentException("Revisa artículo, bodega, cantidad y precio unitario con IVA incluido.");
        await using var c=await connections.OpenAsync(company,false,ct);
        await using var tx=(SqlTransaction)await c.BeginTransactionAsync(IsolationLevel.Serializable,ct);
        await using var q=ZeusRepository.Command(c,"SELECT FacturaVentaId,Contenido FROM ven.FacturaVenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND OperacionGuid=@Key",company,tx);
        ZeusRepository.Add(q,"@Key",input.OperacionGuid);
        await using(var prior=await q.ExecuteReaderAsync(ct))
            if(await prior.ReadAsync(ct))
            {
                if(prior.GetString(1)!=JsonSerializer.Serialize(input))throw new ArgumentException("La clave de operación ya corresponde a otra factura. Actualiza y vuelve a intentarlo.");
                var priorId=prior.GetInt64(0);await prior.CloseAsync();await tx.CommitAsync(ct);
                return new{id=priorId,estado="CONTABILIZADO",repetido=true};
            }
        ZeusRepository.Add(q,"@B",input.SucursalId);ZeusRepository.Add(q,"@C",input.ClienteId);ZeusRepository.Add(q,"@Date",input.FechaContable.ToDateTime(TimeOnly.MinValue));
        q.CommandText="SELECT PeriodoInventarioId FROM core.PeriodoInventario WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND Estado IN('ABIERTO','REABIERTO') AND @Date BETWEEN FechaInicio AND FechaFin";
        var period=await q.ExecuteScalarAsync(ct);
        if(period is null)throw new ArgumentException("Abre el período de la fecha contable antes de facturar.");
        q.CommandText="SELECT Nombre FROM core.Sucursal WHERE EmpresaId=@E AND SucursalId=@B AND Activa=1";
        var branch=await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Selecciona una sucursal activa.");
        q.CommandText="SELECT p.ZeusEstado,t.NumeroIdentificacion,t.RazonSocial FROM ter.Tercero t JOIN ven.ClientePerfil p ON p.EmpresaId=t.EmpresaId AND p.TerceroId=t.TerceroId WHERE t.EmpresaId=@E AND t.TerceroId=@C AND t.Activo=1";
        string customerState,identification,customerName;
        await using(var r=await q.ExecuteReaderAsync(ct))
        {
            if(!await r.ReadAsync(ct))throw new ArgumentException("Selecciona un cliente activo.");
            customerState=r.GetString(0);identification=r.GetString(1);customerName=r.GetString(2);
        }
        if(customerState is not("TERCERO" or "CLIENTE"))throw new ArgumentException("El tercero del cliente debe estar confirmado en Zeus antes de emitir la primera factura.");
        q.CommandText="SELECT Configuracion FROM core.ZeusConfiguracion WHERE EmpresaId=@E";
        var settings=JsonSerializer.Deserialize<ZeusSettings>(await q.ExecuteScalarAsync(ct) as string??throw new ArgumentException("Configura Zeus para esta empresa."))!;
        if(!settings.Habilitado||(settings.FuentesAutomaticas??[]).All(x=>x.Movimiento!="FACTURACION"||x.SucursalId!=input.SucursalId))
            throw new ArgumentException("Configura y habilita la fuente FACTURACION de esta sucursal en Zeus.");
        settings=ZeusRouting.Resolve(settings,input.SucursalId,"FACTURACION",branch);
        var dimensions=await zeus.AccountingDimensionsAsync(company,settings,ct);
        var activeCenters=dimensions.CentrosCosto.Select(x=>x.Codigo).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var requiredCenters=dimensions.CuentasRequierenCentroCosto.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var generalCenter=input.CentroCostoIngreso?.Trim()??"";
        if(generalCenter.Length>0&&!activeCenters.Contains(generalCenter))
            throw new ArgumentException("Selecciona un centro de costo activo y de detalle de Zeus para la factura.");
        var validatedConcepts=new List<(SaleConceptLine Input,string Codigo,string Nombre,string Cuenta)>();
        foreach(var concept in conceptLines)
        {
            q.Parameters.Add("@Concept",SqlDbType.BigInt).Value=concept.ConceptoVentaId;
            q.CommandText="SELECT Codigo,Nombre,CuentaIngresoZeus,ServidorZeus,BaseDatosZeus FROM ven.ConceptoVenta WITH(UPDLOCK,HOLDLOCK) WHERE EmpresaId=@E AND ConceptoVentaId=@Concept AND Activo=1";
            await using(var r=await q.ExecuteReaderAsync(ct))
            {
                if(!await r.ReadAsync(ct))throw new ArgumentException("Un concepto de venta no existe o está inactivo.");
                if(r.GetString(3)!=settings.ServidorEsperado||r.GetString(4)!=settings.BaseEsperada)
                    throw new ArgumentException("Actualiza la cuenta del concepto de venta para la conexión Zeus actual.");
                var code=r.GetString(0);var account=r.GetString(2);
                if(code=="FINANCIACION"&&!account.StartsWith("4135",StringComparison.Ordinal))
                    throw new ArgumentException("La financiación requiere una cuenta 4135.");
                var center=concept.CentroCosto?.Trim()??"";
                if(center.Length>0&&!activeCenters.Contains(center))throw new ArgumentException($"El centro de costo del concepto {code} no está activo o no es de detalle en Zeus.");
                if(requiredCenters.Contains(account)&&center.Length==0)throw new ArgumentException($"Selecciona el centro de costo para el concepto {code}; la cuenta {account} lo exige.");
                validatedConcepts.Add((concept,code,r.GetString(1),account));
            }
            q.Parameters.RemoveAt("@Concept");
        }
        var validated=new List<(SaleItem Input,decimal Base,decimal Iva,decimal Tarifa,bool Inventory,bool Serial,ZeusWarehouseAccounts Accounts)>();
        foreach(var line in input.Lineas)
        {
            q.Parameters.Add("@Article",SqlDbType.BigInt).Value=line.ArticuloId;
            q.Parameters.Add("@Warehouse",SqlDbType.BigInt).Value=line.BodegaId;
            q.CommandText="""
                SELECT a.PorcentajeIvaVenta,a.ManejaInventario,a.ManejaSerial,ISNULL(s.Existencia,0),z.Configuracion,z.Servidor,z.BaseDatos
                FROM inv.Articulo a JOIN inv.Bodega b ON b.EmpresaId=a.EmpresaId AND b.BodegaId=@Warehouse AND b.SucursalId=@B AND b.Activa=1
                LEFT JOIN inv.SaldoArticuloBodega s WITH(UPDLOCK,HOLDLOCK) ON s.EmpresaId=a.EmpresaId AND s.BodegaId=@Warehouse AND s.ArticuloId=a.ArticuloId
                LEFT JOIN core.ZeusBodegaCuenta z ON z.EmpresaId=a.EmpresaId AND z.BodegaId=@Warehouse
                WHERE a.EmpresaId=@E AND a.ArticuloId=@Article AND a.Activo=1;
                """;
            decimal rate,stock;bool inventory,serial;string? accountsJson,server,db;
            await using(var r=await q.ExecuteReaderAsync(ct))
            {
                if(!await r.ReadAsync(ct)||r.IsDBNull(0))throw new ArgumentException("El artículo no existe, no pertenece a la sucursal o no tiene IVA de venta clasificado.");
                rate=r.GetDecimal(0);inventory=r.GetBoolean(1);serial=r.GetBoolean(2);stock=r.GetDecimal(3);
                accountsJson=r.IsDBNull(4)?null:r.GetString(4);server=r.IsDBNull(5)?null:r.GetString(5);db=r.IsDBNull(6)?null:r.GetString(6);
            }
            q.Parameters.RemoveAt("@Article");q.Parameters.RemoveAt("@Warehouse");
            if(inventory&&stock<line.Cantidad)throw new ArgumentException("No hay existencias suficientes en la bodega seleccionada.");
            if(serial&&(line.UnidadesSerializadas?.Length!=line.Cantidad||line.UnidadesSerializadas.Distinct().Count()!=line.UnidadesSerializadas.Length))
                throw new ArgumentException("Selecciona una unidad serializada distinta por cada artículo vendido.");
            if(!serial&&(line.UnidadesSerializadas?.Length??0)>0)throw new ArgumentException("Este artículo no maneja seriales.");
            if(accountsJson is null||server!=settings.ServidorEsperado||db!=settings.BaseEsperada)
                throw new ArgumentException("Configura las cuentas de venta de esta bodega para el destino Zeus actual.");
            var accounts=JsonSerializer.Deserialize<ZeusWarehouseAccounts>(accountsJson)!;
            if(string.IsNullOrWhiteSpace(accounts.CarteraClientes))throw new ArgumentException("Configura la cuenta 13 de clientes en la bodega.");
            var gross=decimal.Round(line.Cantidad*line.PrecioUnitarioConIva,2,MidpointRounding.AwayFromZero);
            var baseValue=decimal.Round(gross/(1+rate/100),2,MidpointRounding.AwayFromZero);
            validated.Add((line,baseValue,gross-baseValue,rate,inventory,serial,accounts));
        }
        if(validated.Select(x=>x.Accounts.CarteraClientes).Distinct().Count()>1)
            throw new ArgumentException("Las bodegas de la factura deben usar la misma cuenta de cartera del cliente.");
        string receivableAccount;
        if(validated.Count>0)receivableAccount=validated[0].Accounts.CarteraClientes!;
        else
        {
            if(input.BodegaCarteraId is not >0)throw new ArgumentException("Selecciona la bodega para tomar la cuenta 13 de clientes de esta venta de conceptos.");
            ZeusRepository.Add(q,"@Warehouse",input.BodegaCarteraId.Value);
            q.CommandText="SELECT z.Configuracion,z.Servidor,z.BaseDatos FROM inv.Bodega b JOIN core.ZeusBodegaCuenta z ON z.EmpresaId=b.EmpresaId AND z.BodegaId=b.BodegaId WHERE b.EmpresaId=@E AND b.BodegaId=@Warehouse AND b.SucursalId=@B AND b.Activa=1";
            string? accountsJson,server,db;
            await using(var r=await q.ExecuteReaderAsync(ct))
            {
                if(!await r.ReadAsync(ct))throw new ArgumentException("Configura las cuentas de venta de la bodega seleccionada.");
                accountsJson=r.GetString(0);server=r.GetString(1);db=r.GetString(2);
            }
            q.Parameters.RemoveAt("@Warehouse");
            if(server!=settings.ServidorEsperado||db!=settings.BaseEsperada)
                throw new ArgumentException("La cuenta de la bodega corresponde a otro destino Zeus.");
            receivableAccount=JsonSerializer.Deserialize<ZeusWarehouseAccounts>(accountsJson)!.CarteraClientes
                ??throw new ArgumentException("Configura la cuenta 13 de clientes de esta bodega.");
            if(!receivableAccount.StartsWith("13",StringComparison.Ordinal))throw new ArgumentException("La cuenta de cartera de esta bodega debe ser clase 13.");
        }
        var conceptsTotal=validatedConcepts.Sum(x=>x.Input.Valor);
        var financeTotal=validatedConcepts.Where(x=>x.Codigo=="FINANCIACION").Sum(x=>x.Input.Valor);
        var total=validated.Sum(x=>x.Base+x.Iva)+conceptsTotal;
        var advanceTotal=advances.Sum(x=>x.Valor);
        if(advanceTotal>total)throw new ArgumentException("El anticipo no puede superar el total de la factura.");
        var balance=total-advanceTotal;
        var schedule=SalesInstallments.BuildWithExtras(input.Vencimiento,input.Cuotas,input.FrecuenciaCuotas,balance,
            input.FechaContable,input.CuotasExtras);
        foreach(var advance in advances.OrderBy(x=>x.ReciboCajaId))
        {
            q.Parameters.Add("@Receipt",SqlDbType.BigInt).Value=advance.ReciboCajaId;
            q.CommandText="SELECT a.Saldo,r.ZeusEstado FROM cxc.AnticipoCliente a WITH(UPDLOCK,HOLDLOCK) JOIN cxc.ReciboCaja r ON r.EmpresaId=a.EmpresaId AND r.ReciboCajaId=a.ReciboCajaId WHERE a.EmpresaId=@E AND a.ReciboCajaId=@Receipt AND a.ClienteId=@C";
            await using(var r=await q.ExecuteReaderAsync(ct))
                if(!await r.ReadAsync(ct)||r.GetDecimal(0)<advance.Valor||r.GetString(1)!="CONTABILIZADO")
                    throw new ArgumentException("El anticipo no pertenece al cliente, no tiene saldo o no está confirmado en Zeus.");
            q.Parameters.RemoveAt("@Receipt");
        }
        ZeusRepository.Add(q,"@N",input.Numero.Trim());ZeusRepository.Add(q,"@Due",input.Vencimiento.ToDateTime(TimeOnly.MinValue));
        ZeusRepository.Add(q,"@Base",validated.Sum(x=>x.Base));ZeusRepository.Add(q,"@Iva",validated.Sum(x=>x.Iva));
        ZeusRepository.Add(q,"@Finance",financeTotal);ZeusRepository.Add(q,"@ConceptsTotal",conceptsTotal);ZeusRepository.Add(q,"@Total",total);ZeusRepository.Add(q,"@Advance",advanceTotal);
        ZeusRepository.Add(q,"@Balance",balance);ZeusRepository.Add(q,"@Terms",input.Cuotas);
        ZeusRepository.Add(q,"@Frequency",input.FrecuenciaCuotas);
        ZeusRepository.Add(q,"@ClaseCartera",input.ClaseCartera);
        ZeusRepository.Add(q,"@Observacion",string.IsNullOrWhiteSpace(input.Observacion)?DBNull.Value:input.Observacion.Trim());
        ZeusRepository.Add(q,"@GeneralCenter",string.IsNullOrEmpty(generalCenter)?DBNull.Value:generalCenter);
        ZeusRepository.Add(q,"@Json",JsonSerializer.Serialize(input));ZeusRepository.Add(q,"@User",user);
        q.CommandText="INSERT ven.FacturaVenta(EmpresaId,OperacionGuid,Numero,SucursalId,ClienteId,FechaContable,Vencimiento,Base,Iva,Financiacion,ConceptosTotal,Total,AnticipoAplicado,SaldoPendiente,Cuotas,FrecuenciaCuotas,CentroCostoIngresoZeus,ClaseCartera,Observacion,Contenido,CreadoPor) OUTPUT inserted.FacturaVentaId VALUES(@E,@Key,@N,@B,@C,@Date,@Due,@Base,@Iva,@Finance,@ConceptsTotal,@Total,@Advance,@Balance,@Terms,@Frequency,@GeneralCenter,@ClaseCartera,@Observacion,@Json,@User)";
        var id=Convert.ToInt64(await q.ExecuteScalarAsync(ct));ZeusRepository.Add(q,"@Id",id);
        foreach(var installment in schedule)
        {
            await using var due=ZeusRepository.Command(c,"INSERT ven.FacturaVentaCuota(EmpresaId,FacturaVentaId,NumeroCuota,FechaVencimiento,ValorOriginal,SaldoPendiente,TipoCuota) VALUES(@E,@Invoice,@Number,@Due,@Value,@Value,@Type)",company,tx);
            ZeusRepository.Add(due,"@Invoice",id);ZeusRepository.Add(due,"@Number",installment.Numero);
            ZeusRepository.Add(due,"@Due",installment.Vencimiento.ToDateTime(TimeOnly.MinValue));ZeusRepository.Add(due,"@Value",installment.Valor);
            ZeusRepository.Add(due,"@Type",installment.Tipo);
            await due.ExecuteNonQueryAsync(ct);
        }
        foreach(var advance in advances)
        {
            q.Parameters.Add("@Receipt",SqlDbType.BigInt).Value=advance.ReciboCajaId;
            q.Parameters.Add("@Value",SqlDbType.Decimal).Value=advance.Valor;
            q.CommandText="UPDATE cxc.AnticipoCliente SET Saldo=Saldo-@Value WHERE EmpresaId=@E AND ReciboCajaId=@Receipt AND ClienteId=@C AND Saldo>=@Value; IF @@ROWCOUNT<>1 THROW 52311,'El anticipo cambió; no se emitió la factura.',1; INSERT ven.FacturaAnticipo(EmpresaId,FacturaVentaId,ReciboCajaId,Valor) VALUES(@E,@Id,@Receipt,@Value)";
            await q.ExecuteNonQueryAsync(ct);q.Parameters.RemoveAt("@Receipt");q.Parameters.RemoveAt("@Value");
        }
        var lineNumber=0;
        var movements=schedule.Select(x=>new ZeusMovement(new ZeusAccount("CLIENTE",receivableAccount,CentroCosto:generalCenter),x.Valor,
            VencimientoCartera:x.Vencimiento.ToDateTime(TimeOnly.MinValue),NumeroCuota:x.Numero)).ToList();
        foreach(var item in validated)
        {
            lineNumber++;
            await using var line=ZeusRepository.Command(c,"INSERT ven.FacturaVentaLinea(EmpresaId,FacturaVentaId,ArticuloId,BodegaId,Cantidad,PrecioConIva,TarifaIva,Base,Iva,UnidadesJson) OUTPUT inserted.FacturaVentaLineaId VALUES(@E,@Invoice,@Article,@Warehouse,@Qty,@Price,@Rate,@Base,@Iva,@Serials)",company,tx);
            foreach(var p in new (string,object)[]{("@Invoice",id),("@Article",item.Input.ArticuloId),("@Warehouse",item.Input.BodegaId),("@Qty",item.Input.Cantidad),("@Price",item.Input.PrecioUnitarioConIva),("@Rate",item.Tarifa),("@Base",item.Base),("@Iva",item.Iva)})ZeusRepository.Add(line,p.Item1,p.Item2);
            line.Parameters.Add("@Serials",SqlDbType.NVarChar,-1).Value=item.Serial?JsonSerializer.Serialize(item.Input.UnidadesSerializadas):DBNull.Value;
            var lineId=Convert.ToInt64(await line.ExecuteScalarAsync(ct));
            movements.Add(new(new ZeusAccount("INGRESO",item.Accounts.Ingreso,CentroCosto:generalCenter),-item.Base));
            if(item.Iva>0)movements.Add(new(new ZeusAccount("IVA_VENTA",item.Accounts.IvaVentas,CentroCosto:generalCenter),-item.Iva,item.Base,item.Tarifa));
            if(!item.Inventory)continue;
            await using var move=c.CreateCommand();move.Transaction=tx;move.CommandType=CommandType.StoredProcedure;
            move.CommandText=item.Serial?"inv.usp_ContabilizarSalidaSerializada":"inv.usp_ContabilizarSalida";
            void Add(string name,object value)=>move.Parameters.AddWithValue(name,value);
            Add("@EmpresaId",company);Add("@BodegaId",item.Input.BodegaId);Add("@ArticuloId",item.Input.ArticuloId);
            Add("@PeriodoInventarioId",Convert.ToInt64(period));Add("@FechaMovimiento",input.FechaContable.ToDateTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(12))));
            Add("@FechaContable",input.FechaContable.ToDateTime(TimeOnly.MinValue));Add("@TipoMovimiento","VENTA");
            Add("@ModuloOrigen","VENTAS");Add("@TipoDocumentoOrigen","FACTURA_VENTA");Add("@DocumentoOrigenId",id);
            Add("@DocumentoLineaOrigenId",lineId);Add("@NumeroDocumento",input.Numero.Trim());Add("@TerceroId",input.ClienteId);
            Add("@CantidadSalida",item.Input.Cantidad);var moveKey=Guid.NewGuid();Add("@IdempotencyKey",moveKey);Add("@UsuarioId",user);
            if(item.Serial)Add("@UnidadesJson",JsonSerializer.Serialize(item.Input.UnidadesSerializadas));
            await using(var reader=await move.ExecuteReaderAsync(ct))do{while(await reader.ReadAsync(ct)){}}while(await reader.NextResultAsync(ct));
            await using var cost=ZeusRepository.Command(c,"SELECT ABS(ValorMovimiento) FROM inv.MovimientoInventario WHERE EmpresaId=@E AND IdempotencyKey=@Move",company,tx);
            ZeusRepository.Add(cost,"@Move",moveKey);var value=await cost.ExecuteScalarAsync(ct);
            if(value is null)throw new InvalidOperationException("La salida de inventario no confirmó su costo.");
            await using var update=ZeusRepository.Command(c,"UPDATE ven.FacturaVentaLinea SET Costo=@Cost WHERE EmpresaId=@E AND FacturaVentaLineaId=@Line",company,tx);
            var costValue=decimal.Round(Convert.ToDecimal(value),2,MidpointRounding.AwayFromZero);
            ZeusRepository.Add(update,"@Cost",costValue);ZeusRepository.Add(update,"@Line",lineId);await update.ExecuteNonQueryAsync(ct);
            if(costValue>0)
            {
                movements.Add(new(new ZeusAccount("COSTO_VENTA",item.Accounts.CostoVenta,CentroCosto:generalCenter),costValue));
                movements.Add(new(new ZeusAccount("INVENTARIO",item.Accounts.Inventario,CentroCosto:generalCenter),-costValue));
            }
        }
        foreach(var concept in validatedConcepts)
        {
            await using var conceptInsert=ZeusRepository.Command(c,"INSERT ven.FacturaVentaConcepto(EmpresaId,FacturaVentaId,ConceptoVentaId,Codigo,Nombre,CuentaIngresoZeus,CentroCostoZeus,Valor) VALUES(@E,@Invoice,@Concept,@Code,@Name,@Account,@Center,@Value)",company,tx);
            ZeusRepository.Add(conceptInsert,"@Invoice",id);ZeusRepository.Add(conceptInsert,"@Concept",concept.Input.ConceptoVentaId);
            ZeusRepository.Add(conceptInsert,"@Code",concept.Codigo);ZeusRepository.Add(conceptInsert,"@Name",concept.Nombre);
            ZeusRepository.Add(conceptInsert,"@Account",concept.Cuenta);ZeusRepository.Add(conceptInsert,"@Center",string.IsNullOrWhiteSpace(concept.Input.CentroCosto)?DBNull.Value:concept.Input.CentroCosto.Trim());ZeusRepository.Add(conceptInsert,"@Value",concept.Input.Valor);
            await conceptInsert.ExecuteNonQueryAsync(ct);
            movements.Add(new(new ZeusAccount("CONCEPTO_"+concept.Codigo,concept.Cuenta,CentroCosto:concept.Input.CentroCosto?.Trim()??""),-concept.Input.Valor));
        }
        if(advanceTotal>0)
        {
            var advanceAccount=ZeusJournal.GeneralAdvanceAccount(settings)?.Cuenta
                ??throw new ArgumentException("Configura la cuenta general de anticipos antes de aplicarlos en factura.");
            movements.Add(new(new ZeusAccount("ANTICIPO",advanceAccount,CentroCosto:generalCenter),advanceTotal));
        }
        var missingCenter=movements.FirstOrDefault(x=>requiredCenters.Contains(x.Regla.Cuenta)&&string.IsNullOrWhiteSpace(x.Regla.CentroCosto));
        if(missingCenter is not null)throw new ArgumentException($"Selecciona el centro de costo para {missingCenter.Regla.Concepto}; la cuenta {missingCenter.Regla.Cuenta} lo exige.");
        if(movements.Sum(x=>x.Valor)!=0)throw new InvalidOperationException("La factura no quedó balanceada. No se contabilizó.");
        var source=new ZeusSource(0,input.ClienteId,input.Numero.Trim(),input.FechaContable.ToDateTime(TimeOnly.MinValue),input.FechaContable.ToDateTime(TimeOnly.MinValue),input.Vencimiento.ToDateTime(TimeOnly.MinValue),total,validated.Sum(x=>x.Iva),0,[],ProveedorNombre:customerName);
        var snapshot=new ZeusSnapshot(settings,source,new(input.ClienteId,identification,identification),movements.ToArray(),
            ClienteDocumento:new("FACTURA","FACTURA DE VENTA",receivableAccount,FacturaUsaConsecutivoZeus:true,CarteraConsecutivoCompleto:true));
        q.CommandText="UPDATE ven.FacturaVenta SET Snapshot=@Snapshot WHERE EmpresaId=@E AND FacturaVentaId=@Id";
        ZeusRepository.Add(q,"@Snapshot",JsonSerializer.Serialize(snapshot));await q.ExecuteNonQueryAsync(ct);
        q.CommandText="INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen) VALUES(@E,@User,'CONTABILIZAR_FACTURA_VENTA','ven.FacturaVenta',CONVERT(varchar(30),@Id),@Json,'ERP')";
        await q.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);
        return new{id,numero=input.Numero,estado="CONTABILIZADO",zeusEstado="PENDIENTE",total,saldo=balance,cuotas=schedule.Length,repetido=false};
    }
}
