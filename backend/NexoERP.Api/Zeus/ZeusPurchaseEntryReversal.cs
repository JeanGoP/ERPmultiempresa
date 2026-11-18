using System.Data;
using System.Globalization;
using Microsoft.Data.SqlClient;

namespace NexoERP.Api.Zeus;

public static class ZeusPurchaseEntryReversalPolicy
{
    public static ZeusSnapshot Build(ZeusSnapshot original,Guid originalKey,string source,string document,DateOnly date,string reason)
    {
        if(original.ReversionEntrada is not null||original.Egreso is not null||original.ClienteDocumento is not null
           ||original.NotaCartera is not null||original.Traslado is not null)
            throw new ArgumentException("El comprobante original no corresponde a una entrada de mercancía independiente.");
        if(originalKey==Guid.Empty||source!=original.Configuracion.Fuente||string.IsNullOrWhiteSpace(document)||document.Trim().Length>10)
            throw new ArgumentException("La entrada carece de una identificación confirmada del comprobante original de Zeus.");
        if(original.Movimientos.Length<2||original.Movimientos.Sum(line=>line.Valor)!=0||original.Origen.Total<=0
           ||original.Movimientos.Count(line=>line.Regla.Concepto=="PROVEEDOR")!=1
           ||original.Movimientos.Single(line=>line.Regla.Concepto=="PROVEEDOR").Valor!=-original.Origen.Total)
            throw new ArgumentException("El comprobante original no conserva un saldo de proveedor válido y balanceado.");
        var reversal=original with {
            Origen=original.Origen with {FechaContable=date.ToDateTime(TimeOnly.MinValue)},
            Movimientos=original.Movimientos.Select(line=>line with {Valor=-line.Valor,Base=-line.Base}).ToArray(),
            ReversionEntrada=new(original.Origen.RecepcionId,originalKey,source,document.Trim(),original.Origen.FechaContable,reason.Trim())
        };
        Validate(reversal);
        return reversal;
    }

    public static ZeusSnapshot Original(ZeusSnapshot reversal)
    {
        var source=reversal.ReversionEntrada??throw new ArgumentException("Falta la referencia del comprobante original.");
        return reversal with {
            Origen=reversal.Origen with {FechaContable=source.FechaContableOriginal},
            Movimientos=reversal.Movimientos.Select(line=>line with {Valor=-line.Valor,Base=-line.Base}).ToArray(),
            ReversionEntrada=null
        };
    }

    public static void Validate(ZeusSnapshot snapshot)
    {
        if(snapshot.ReversionEntrada is not { } reversal)return;
        if(snapshot.Egreso is not null||snapshot.ClienteDocumento is not null||snapshot.NotaCartera is not null||snapshot.Traslado is not null
           ||reversal.RecepcionMercanciaId!=snapshot.Origen.RecepcionId||reversal.ClaveOriginal==Guid.Empty
           ||reversal.FuenteOriginal!=snapshot.Configuracion.Fuente||string.IsNullOrWhiteSpace(reversal.DocumentoOriginal)
           ||reversal.Motivo.Length is <10 or >500||snapshot.Origen.FechaContable.Date<reversal.FechaContableOriginal.Date
           ||snapshot.Movimientos.Sum(line=>line.Valor)!=0||snapshot.Origen.Total<=0
           ||snapshot.Movimientos.Count(line=>line.Regla.Concepto=="PROVEEDOR")!=1
           ||snapshot.Movimientos.Single(line=>line.Regla.Concepto=="PROVEEDOR").Valor!=snapshot.Origen.Total)
            throw new ArgumentException("La reversión de entrada no conserva un comprobante original válido.");
    }
}

public sealed partial class ZeusTransport
{
    public async Task CheckPurchaseEntryReversalAsync(long company,ZeusSnapshot reversal,CancellationToken ct)
    {
        ZeusPurchaseEntryReversalPolicy.Validate(reversal);
        await using var connection=await OpenAsync(company,reversal.Configuracion,ct);
        await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(ct);
        await CheckPurchaseEntryReversalAsync(connection,transaction,reversal,ct);
        await transaction.RollbackAsync(ct);
    }

    private static async Task CheckPurchaseEntryReversalAsync(SqlConnection connection,SqlTransaction transaction,ZeusSnapshot reversal,CancellationToken ct)
    {
        var reference=reversal.ReversionEntrada??throw new ArgumentException("Falta el comprobante original de la entrada.");
        var original=ZeusPurchaseEntryReversalPolicy.Original(reversal);
        var document=await VerifyAsync(connection,transaction,original,reference.ClaveOriginal,ct);
        if(document!=reference.DocumentoOriginal)
            throw new ArgumentException("No se confirmó en Zeus el comprobante original de esta entrada. Revisa su conciliación.");
        await VerifyPurchaseEntryLinesAsync(connection,transaction,original,document,ct);

        var payable=original.Movimientos.Single(line=>line.Regla.Concepto=="PROVEEDOR");
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="""
            SELECT TOP(1) f.SACTFAC
            FROM dbo.FACTURAS_BU f WITH(UPDLOCK,HOLDLOCK)
            JOIN dbo.PROVEEDORES p ON p.IDPROVE=f.IDCLIPRV AND p.IDTERCERO=@Third
            WHERE f.BU=@Bu AND f.CODICTA=@Account AND f.IDUNIDAD='' AND f.IDCLIPRV=@Supplier
              AND f.TIPOFACT=@Type AND f.NUMEFAC=@Invoice AND f.VENCFAC=@Due
              AND ISNULL(f.REFEFAC,'')=@Reference
            ORDER BY f.ANOMESFAC DESC;
            SELECT SUM(t.VALORTRA)
            FROM dbo.TRANSAC t WITH(UPDLOCK,HOLDLOCK)
            WHERE t.BU=@Bu AND t.CODICTA=@Account AND t.CLIPRV=@Supplier AND t.NITTRA=@Third
              AND t.TIPOFAC=@Type AND t.NUMEFAC=@Invoice AND t.VENCEFAC=@Due
              AND ISNULL(t.REFEFAC,'')=@Reference AND t.STATUSTRA IN('AC','XA');
            """;
        command.Parameters.AddWithValue("@Bu",original.Configuracion.UnidadNegocio);
        command.Parameters.AddWithValue("@Account",payable.Regla.Cuenta);
        command.Parameters.AddWithValue("@Third",string.IsNullOrWhiteSpace(payable.Regla.TerceroCodigo)?original.Proveedor.CodigoTercero:payable.Regla.TerceroCodigo);
        command.Parameters.AddWithValue("@Supplier",string.IsNullOrWhiteSpace(payable.Regla.ClienteProveedorCodigo)?original.Proveedor.CodigoProveedor:payable.Regla.ClienteProveedorCodigo);
        command.Parameters.AddWithValue("@Type",original.Configuracion.TipoFactura);
        command.Parameters.AddWithValue("@Invoice",original.Origen.Factura);
        command.Parameters.Add("@Due",SqlDbType.VarChar,10).Value=(payable.VencimientoCartera??original.Origen.Vencimiento).ToString("yyyy/MM/dd",CultureInfo.InvariantCulture);
        command.Parameters.AddWithValue("@Reference","");
        await using var reader=await command.ExecuteReaderAsync(ct);
        if(!await reader.ReadAsync(ct)||reader.IsDBNull(0)||reader.GetDecimal(0)!=-original.Origen.Total)
            throw new ArgumentException("La factura tiene pagos, notas o un saldo diferente en Zeus. Revisa la obligación antes de revertir la entrada.");
        await reader.NextResultAsync(ct);
        if(!await reader.ReadAsync(ct)||reader.IsDBNull(0)||reader.GetDecimal(0)!=-original.Origen.Total)
            throw new ArgumentException("Los movimientos de la factura en Zeus registran pagos o ajustes. La entrada no puede revertirse.");
    }

    private sealed record PurchaseLineKey(string Account,string Third,string Supplier,string Indicator,string Type,string Invoice,
        DateTime Due,string Reference,string BusinessUnit,string Center,string Auxiliary,string Item,string Budget,string Reserve,decimal Rate,int Sign);

    private static async Task VerifyPurchaseEntryLinesAsync(SqlConnection connection,SqlTransaction? transaction,ZeusSnapshot snapshot,string document,CancellationToken ct)
    {
        var expected=snapshot.Movimientos.GroupBy(line=>new PurchaseLineKey(
            line.Regla.Cuenta.Trim(),string.IsNullOrWhiteSpace(line.Regla.TerceroCodigo)?snapshot.Proveedor.CodigoTercero:line.Regla.TerceroCodigo,
            string.IsNullOrWhiteSpace(line.Regla.ClienteProveedorCodigo)?snapshot.Proveedor.CodigoProveedor:line.Regla.ClienteProveedorCodigo,
            line.Regla.Concepto=="PROVEEDOR"?"3":"1",snapshot.Configuracion.TipoFactura,snapshot.Origen.Factura,
            (line.VencimientoCartera??snapshot.Origen.Vencimiento).Date,"",snapshot.Configuracion.UnidadNegocio,
            line.Regla.CentroCosto,line.Regla.Auxiliar,line.Regla.Item,line.Regla.Presupuesto,line.Regla.Reserva,line.Tarifa,Math.Sign(line.Valor)))
            .ToDictionary(group=>group.Key,group=>(Amount:group.Sum(line=>line.Valor),Basis:group.Sum(line=>line.Base)));
        await using var command=connection.CreateCommand();command.Transaction=transaction;
        command.CommandText="""
            SELECT RTRIM(CODICTA),ISNULL(RTRIM(NITTRA),''),ISNULL(RTRIM(CLIPRV),''),ISNULL(RTRIM(INDCPITRA),''),
                   ISNULL(RTRIM(TIPOFAC),''),ISNULL(RTRIM(NUMEFAC),''),CONVERT(date,NULLIF(RTRIM(VENCEFAC),'')),
                   ISNULL(RTRIM(REFEFAC),''),ISNULL(RTRIM(BU),''),ISNULL(RTRIM(IDCENCO),''),
                   ISNULL(RTRIM(AUXIAUX),''),ISNULL(RTRIM(IDITEM),''),ISNULL(RTRIM(CODPRESU),''),ISNULL(RTRIM(NRESERVA),''),
                   ISNULL(PORRETETRA,0),VALORTRA,ISNULL(BASERETETRA,0)
            FROM dbo.TRANSAC
            WHERE IDFUENTE=@Source AND NUMDOCTRA=@Document AND ANOTRA=@Period AND STATUSTRA IN('AC','XA');
            """;
        command.Parameters.AddWithValue("@Source",snapshot.Configuracion.Fuente);
        command.Parameters.AddWithValue("@Document",document);
        command.Parameters.AddWithValue("@Period",snapshot.Origen.FechaContable.ToString("yyyyMM",CultureInfo.InvariantCulture));
        var actual=new Dictionary<PurchaseLineKey,(decimal Amount,decimal Basis)>();
        await using(var reader=await command.ExecuteReaderAsync(ct))
        {
            while(await reader.ReadAsync(ct))
            {
                var amount=reader.GetDecimal(15);
                var key=new PurchaseLineKey(reader.GetString(0),reader.GetString(1),reader.GetString(2),reader.GetString(3),
                    reader.GetString(4),reader.GetString(5),reader.IsDBNull(6)?DateTime.MinValue:reader.GetDateTime(6),
                    reader.GetString(7),reader.GetString(8),reader.GetString(9),reader.GetString(10),reader.GetString(11),
                    reader.GetString(12),reader.GetString(13),reader.GetDecimal(14),Math.Sign(amount));
                var previous=actual.GetValueOrDefault(key);
                actual[key]=(previous.Amount+amount,previous.Basis+reader.GetDecimal(16));
            }
        }
        if(expected.Count!=actual.Count||expected.Any(entry=>!actual.TryGetValue(entry.Key,out var value)||value!=entry.Value))
            throw new InvalidOperationException("Zeus no confirmó las cuentas, impuestos y referencias exactas de la entrada de mercancía.");
    }
}
