using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Treasury;

namespace NexoERP.Api.Zeus;
public sealed record ZeusCashAccount(string Codigo,string Nombre,string Banco,int Indicador,string CuentaBancaria);
public sealed record ZeusPaymentCurrency(string Codigo,string Nombre,int Tipo);
public sealed partial class ZeusTransport : IDisbursementCheck
{
    public async Task<ZeusCashAccount[]> CashAccountsAsync(long company,ZeusSettings settings,CancellationToken ct)
    {
        await using var c=await OpenAsync(company,settings,ct);return await CashAccounts(c,null,ct);
    }
    private static async Task<ZeusCashAccount[]> CashAccounts(SqlConnection c,SqlTransaction? tx,CancellationToken ct)
    {
        await using var q=c.CreateCommand();q.Transaction=tx;q.CommandText="SELECT RTRIM(CODICTA),RTRIM(DESCCTA),RTRIM(ISNULL(IDBANCO,'')),ISNULL(INDCPICTA,1),RTRIM(ISNULL(CTACORRIENTE,'')) FROM dbo.MAECONT WHERE HABILITARCTA=1 AND TIPOCTA='D' AND ISNULL(IDMONEDA,'')='' AND (INDCPICTA=6 OR (INDCPICTA=1 AND ISNULL(IDBANCO,'')<>'')) ORDER BY CODICTA";
        var list=new List<ZeusCashAccount>();await using var r=await q.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetString(0),r.GetString(1),r.GetString(2),Convert.ToInt32(r[3]),r.GetString(4)));return list.ToArray();
    }
    public async Task<ZeusPaymentCurrency[]> PaymentCurrenciesAsync(long company,ZeusSettings settings,CancellationToken ct)
    {
        await using var c=await OpenAsync(company,settings,ct);await using var q=c.CreateCommand();q.CommandText="SELECT RTRIM(IDMONEDA),RTRIM(DESCRIP),SIMONEDA FROM dbo.MONEDAS WHERE Deshabilitado=0 ORDER BY IDMONEDA";
        var list=new List<ZeusPaymentCurrency>();await using var r=await q.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetString(0),r.GetString(1),Convert.ToInt32(r[2])));return list.ToArray();
    }
    public async Task CheckDisbursementAsync(long company,ZeusSnapshot snapshot,CancellationToken ct)
    {
        await using var c=await OpenAsync(company,snapshot.Configuracion,ct);
        if(snapshot.Proveedor.CodigoProveedor==snapshot.Proveedor.CodigoTercero)
        {
            var supplier=await SupplierExists(c,null,snapshot.Proveedor.CodigoProveedor,ct);
            if(!supplier.Third||!supplier.Supplier)throw new ArgumentException("Envía primero el proveedor a Zeus desde su maestro.");
        }
        await CheckPayment(c,null,snapshot,ct);
        foreach(var invoice in snapshot.Egreso!.Facturas)
        {
            var balance=await InvoiceBalance(c,null,snapshot,invoice,ct);
            if(balance>=0||-balance<invoice.Valor)throw new ArgumentException($"La factura {invoice.Numero} no tiene saldo suficiente en Zeus en el período del pago. No se contabilizó el egreso.");
        }
    }
    private static async Task<ZeusSnapshot> CheckPayment(SqlConnection c,SqlTransaction? tx,ZeusSnapshot s,CancellationToken ct)
    {
        var payment=s.Egreso!;
        if(payment is null||s.Movimientos.Sum(m=>m.Valor)!=0)throw new ArgumentException("Egreso sin balance contable válido.");
        var account=(await CashAccounts(c,tx,ct)).SingleOrDefault(a=>a.Codigo==payment.CuentaSalida)??throw new ArgumentException("Cuenta de caja/banco no habilitada en Zeus.");
        if(account.Banco!=payment.Banco)throw new ArgumentException("El banco asociado a la cuenta cambió en Zeus; revisa la configuración.");
        await using var q=c.CreateCommand();q.Transaction=tx;
        q.CommandText="SELECT COUNT(*) FROM dbo.FUENTES WHERE IDFUENTE=@F AND IDTIPDOC='003' AND Deshabilitado=0";q.Parameters.AddWithValue("@F",s.Configuracion.Fuente);
        if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new ArgumentException("La fuente de la sucursal no es un comprobante de egreso habilitado en Zeus (tipo 003).");
        q.CommandText="SELECT SIMONEDA FROM dbo.MONEDAS WHERE IDMONEDA=@M AND Deshabilitado=0";q.Parameters.AddWithValue("@M",payment.MonedaZeus);
        var kind=await q.ExecuteScalarAsync(ct);if(kind is null)throw new ArgumentException("El medio de pago configurado no está habilitado en Zeus.");
        if(Convert.ToInt32(kind) is not(0 or 1)&&string.IsNullOrWhiteSpace(payment.Referencia))throw new ArgumentException("Ingresa la referencia de transferencia o el número de cheque.");
        foreach(var movement in s.Movimientos)
        {
            q.Parameters.Clear();q.CommandText="SELECT COUNT(*) FROM dbo.MAECONT WHERE CODICTA=@A AND HABILITARCTA=1 AND TIPOCTA='D' AND ISNULL(INDCCOCTA,0)<>1 AND ISNULL(ExigeItem,0)=0 AND ((@P=1 AND INDCPICTA=3) OR (@P=0 AND @Cash=1 AND INDCPICTA IN(1,6)) OR (@P=0 AND @Cash=0 AND INDCPICTA=1 AND ISNULL(PORCEIMPUESTO,0)=0 AND ISNULL(IDBANCO,'')=''))";
            q.Parameters.AddWithValue("@A",movement.Regla.Cuenta);q.Parameters.AddWithValue("@P",movement.Regla.Concepto=="PROVEEDOR"?1:0);q.Parameters.AddWithValue("@Cash",movement.Regla.Concepto=="BANCO_CAJA"?1:0);
            if(Convert.ToInt32(await q.ExecuteScalarAsync(ct))!=1)throw new ArgumentException($"Cuenta {movement.Regla.Cuenta} no habilitada o exige datos adicionales. Los gastos directos no admiten impuestos ni cuentas de cartera/caja.");
        }
        return s with{Egreso=payment with{IndicadorSalida=account.Indicador,CuentaBancaria=account.CuentaBancaria}};
    }
    // Clave completa usada por el procedimiento original SpPagosACartera del propietario.
    private static async Task<decimal> InvoiceBalance(SqlConnection c,SqlTransaction? tx,ZeusSnapshot s,ZeusPaymentInvoice invoice,CancellationToken ct)
    {
        await using var q=c.CreateCommand();q.Transaction=tx;q.CommandText="SELECT SUM(Sactfac) FROM dbo.Facturas_Bu WITH(HOLDLOCK) WHERE Anomesfac=@Period AND IdCliprv=@Supplier AND Codicta=@Account AND tipofact=@Type AND numefac=@Invoice AND refefac=@Ref AND Idunidad='' AND Bu=@Bu";
        foreach(var p in new (string,object)[]{("@Period",s.Origen.FechaContable.ToString("yyyyMM")),("@Supplier",s.Proveedor.CodigoProveedor),("@Account",invoice.Cuenta),("@Type",invoice.Tipo),("@Invoice",invoice.Numero),("@Ref",invoice.Referencia),("@Bu",invoice.UnidadNegocio)})q.Parameters.AddWithValue(p.Item1,p.Item2);
        var balance=await q.ExecuteScalarAsync(ct);
        if(balance is null or DBNull)throw new ArgumentException($"No existe saldo verificable para la factura {invoice.Numero} en Zeus en el período del pago. Revisa su cuenta, proveedor y unidad de negocio.");
        return Convert.ToDecimal(balance);
    }
    private static async Task VerifyPaymentLines(SqlConnection c,SqlTransaction? tx,ZeusSnapshot s,string number,CancellationToken ct)
    {
        foreach(var invoice in s.Egreso!.Facturas)
        {
            await using var q=c.CreateCommand();q.Transaction=tx;q.CommandText="SELECT SUM(VALORTRA) FROM dbo.TRANSAC WHERE IDFUENTE=@F AND NUMDOCTRA=@N AND CODICTA=@A AND CLIPRV=@P AND NITTRA=@T AND TIPOFAC=@Type AND NUMEFAC=@Invoice AND ISNULL(REFEFAC,'')=@Ref AND BU=@Bu AND INDCPITRA='3' AND STATUSTRA IN('AC','XA')";
            foreach(var p in new (string,object)[]{("@F",s.Configuracion.Fuente),("@N",number),("@A",invoice.Cuenta),("@P",s.Proveedor.CodigoProveedor),("@T",s.Proveedor.CodigoTercero),("@Type",invoice.Tipo),("@Invoice",invoice.Numero),("@Ref",invoice.Referencia),("@Bu",invoice.UnidadNegocio)})q.Parameters.AddWithValue(p.Item1,p.Item2);
            var value=await q.ExecuteScalarAsync(ct);if(value is null or DBNull||Convert.ToDecimal(value)!=invoice.Valor)throw new InvalidOperationException($"Zeus no confirmó la aplicación exacta a la factura {invoice.Numero}.");
        }
    }
}
