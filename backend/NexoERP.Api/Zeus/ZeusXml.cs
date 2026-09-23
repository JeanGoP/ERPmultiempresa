using System.Globalization;
using System.Text;
using System.Xml.Linq;

namespace NexoERP.Api.Zeus;

// Contrato /ZEUS_SQL/Documento del spWSG_ProcesarComprobantes entregado por el propietario.
// Se envían movimientos explícitos; no se invocan escenarios fiscales de ventas.
public static class ZeusXml
{
    private const string HeaderText="ANODCTO FNTEDCTO NUMEDCTO FECHDCTO IACTDCTO DESCDCTO IDCENCO IDTERCERO IDCLIPRV IDBANCO CBADCTO CHEDCTO ENTREGADO TPRECDCTO NDRECDCTO ENFDCTO AUXILIAR ITEM STATUSDCTO BENEFDCTO IMPRICHEQUE MONTOLETRAS AjusteInflacion IndContabPrestamo NCF NCF_Modificado Moneda MontoMoneda VencCheque bu Aplicacion XmlAdicionales";
    private const string HeaderNumber="VCHDCTO NReversiones Paag_Mes Paag_Acu NumVales NumValesConciliados VrMoneda TasaCambio Id_AplicacionesZeus";
    private const string DetailText="ANOTRA IDFUENTE NUMDOCTRA FECHATRA CODICTA NITTRA NITTRAG AUXIAUX IDCENCO IDITEM DESCRITRA INDCPITRA CONCILTRA IDBANCO IDVENDE IDPLAZA TIPOFAC NUMEFAC VENCEFAC REFEFAC IDUSUARIO IDZONA CLIPRV CODPRESU NRESERVA STATUSTRA IDUNIDAD1 IDUNIDAD2 IDUNIDAD3 Serie Autorizacion Fechafact Adicional_1 Adicional_2 Voucher BU NCF NCF_Modificado FechaCaducidad OrigenError CompRete_Serie CompRete_Secuencial CompRete_FechaEmision CompRete_Autorizacion Aplicacion XmlAdicionales MovimientoPorCosolidacion CodigoPropiedad1 CodigoPropiedad2 CodigoPropiedad3 CodigoPropiedad4 CodigoPropiedad5 Revelacion Id_Movimiento LineaImpuesto SubLineaImpuesto";
    private const string DetailNumber="VALORTRA PORRETETRA BASERETETRA VALORMONEDA VALORUTRA1 VALORUTRA2 VALORUTRA3 TasaCambio BaseComision Id_AplicacionesOrigen VALORMONEDA1 VALORMONEDA2 TASACAMBIO1 TASACAMBIO2 fact_movimiento_original Id_AplicacionesZeus Id_OrigenMovimiento fact_porcentaje_interes_pactado fact_porcentaje_interes_comparativo fact_idencondicionesdecredito cuota plazo ValorPrestamo ValorCuota CostosAsociados CuotasGracia ConsecutivoCredito Iden_Secciones";
    public static string Marker(Guid key)=>"NEXO:"+key.ToString("N");
    public static string Description(ZeusSource source)
    {
        const string prefix="ENTRADA DE MERCANCIA - ";
        var suffix=" - "+source.Factura;
        var name=string.Join(" ",(source.ProveedorNombre??"").Split((char[]?)null,StringSplitOptions.RemoveEmptyEntries));
        var available=120-prefix.Length-suffix.Length;
        if(name.Length>available)name=name[..available];
        return prefix+name+suffix;
    }
    public static string Build(ZeusSnapshot s,Guid key)
    {
        var config=s.Configuracion;var origin=s.Origen;
        var date=origin.FechaContable.ToString("yyyy/MM/dd",CultureInfo.InvariantCulture);
        var period=origin.FechaContable.ToString("yyyyMM",CultureInfo.InvariantCulture);
        var number=config.Serie+"NUEVO";
        XElement Create(string name,string texts,string numbers)=>new(name,texts.Split(' ').Select(n=>new XElement(n,"")),numbers.Split(' ').Select(n=>new XElement(n,"0")));
        void Set(XElement e,string name,object value)=>e.SetElementValue(name,value is decimal d?ZeusJournal.Number(d):value);
        var header=Create("Document",HeaderText,HeaderNumber);
        Set(header,"ANODCTO",period);Set(header,"FNTEDCTO",config.Fuente);Set(header,"NUMEDCTO",number);
        Set(header,"FECHDCTO",date);Set(header,"DESCDCTO",origin.ProveedorNombre is null?Marker(key):Description(origin));Set(header,"IDTERCERO",s.Proveedor.CodigoTercero);
        if(origin.ProveedorNombre is not null)Set(header,"XmlAdicionales",Marker(key));
        Set(header,"IDCLIPRV",s.Proveedor.CodigoProveedor);Set(header,"bu",config.UnidadNegocio);
        Set(header,"IACTDCTO","S");Set(header,"STATUSDCTO","AC");Set(header,"TasaCambio",1);Set(header,"Aplicacion","CONTABILIDAD");
        var document=new XElement("Documento",header,new XElement("General",new XElement("AgruparNIT","N")));
        foreach(var movement in s.Movimientos)
        {
            var a=movement.Regla;var line=Create("Transac",DetailText,DetailNumber);
            Set(line,"ANOTRA",period);Set(line,"IDFUENTE",config.Fuente);Set(line,"NUMDOCTRA",number);Set(line,"FECHATRA",date);
            Set(line,"CODICTA",a.Cuenta);Set(line,"NITTRA",s.Proveedor.CodigoTercero);Set(line,"CLIPRV",s.Proveedor.CodigoProveedor);
            Set(line,"DESCRITRA",$"Factura {origin.Factura} - {a.Concepto}");Set(line,"OrigenError",$"Entrada {origin.RecepcionId} {a.Concepto}");
            Set(line,"BU",config.UnidadNegocio);Set(line,"IDUSUARIO",config.UsuarioZeus);Set(line,"TIPOFAC",config.TipoFactura);
            Set(line,"NUMEFAC",origin.Factura);Set(line,"VENCEFAC",origin.Vencimiento.ToString("yyyy/MM/dd",CultureInfo.InvariantCulture));
            Set(line,"Fechafact",origin.FechaFactura.ToString("yyyy/MM/dd",CultureInfo.InvariantCulture));Set(line,"STATUSTRA","XA");
            Set(line,"INDCPITRA",a.Concepto=="PROVEEDOR"?"3":"1");Set(line,"VALORTRA",movement.Valor);
            Set(line,"BASERETETRA",movement.Base);Set(line,"PORRETETRA",movement.Tarifa);Set(line,"TasaCambio",1);
            Set(line,"IDCENCO",a.CentroCosto);Set(line,"AUXIAUX",a.Auxiliar);Set(line,"IDITEM",a.Item);
            Set(line,"CODPRESU",a.Presupuesto);Set(line,"NRESERVA",a.Reserva);Set(line,"Aplicacion","CONTABILIDAD");
            document.Add(line);
        }
        if(s.Egreso is { } payment)
        {
            Set(header,"DESCDCTO",("COMPROBANTE DE EGRESO - "+origin.ProveedorNombre)[..Math.Min(120,("COMPROBANTE DE EGRESO - "+origin.ProveedorNombre).Length)]);
            Set(header,"XmlAdicionales",Marker(key));Set(header,"IDBANCO",payment.Banco);
            Set(header,"BENEFDCTO",origin.ProveedorNombre??s.Proveedor.CodigoTercero);
            Set(header,"VCHDCTO",origin.Total);Set(header,"CHEDCTO",payment.Referencia);
            Set(header,"CBADCTO",payment.CuentaBancaria);Set(header,"Moneda",payment.MonedaZeus);Set(header,"VrMoneda",origin.Total);
            document.Elements("Transac").Remove();
            void PaymentLine(ZeusMovement m,ZeusPaymentInvoice? invoice)
            {
                var line=Create("Transac",DetailText,DetailNumber);
                Set(line,"ANOTRA",period);Set(line,"IDFUENTE",config.Fuente);Set(line,"NUMDOCTRA",number);Set(line,"FECHATRA",date);
                Set(line,"CODICTA",m.Regla.Cuenta);Set(line,"NITTRA",s.Proveedor.CodigoTercero);Set(line,"CLIPRV",invoice is null?"":s.Proveedor.CodigoProveedor);
                Set(line,"DESCRITRA",invoice is null?payment.Concepto[..Math.Min(120,payment.Concepto.Length)]:"ABONO FACTURA "+invoice.Numero);
                Set(line,"BU",invoice?.UnidadNegocio??config.UnidadNegocio);Set(line,"IDUSUARIO",config.UsuarioZeus);
                Set(line,"STATUSTRA","XA");Set(line,"INDCPITRA",invoice is null?"1":"3");Set(line,"VALORTRA",m.Valor);Set(line,"TasaCambio",1);Set(line,"Aplicacion","CONTABILIDAD");
                if(m.Valor<0){Set(line,"IDBANCO",payment.Banco);Set(line,"INDCPITRA",payment.IndicadorSalida);Set(line,"TIPOFAC",payment.MonedaZeus);Set(line,"NUMEFAC",payment.Referencia);Set(line,"VENCEFAC",date);Set(line,"VALORMONEDA",m.Valor);}
                if(invoice is not null){Set(line,"TIPOFAC",invoice.Tipo);Set(line,"NUMEFAC",invoice.Numero);Set(line,"REFEFAC",invoice.Referencia);Set(line,"VENCEFAC",invoice.Vencimiento.ToString("yyyy/MM/dd",CultureInfo.InvariantCulture));}
                document.Add(line);
            }
            foreach(var invoice in payment.Facturas)PaymentLine(new(new ZeusAccount("PROVEEDOR",invoice.Cuenta),invoice.Valor),invoice);
            foreach(var movement in s.Movimientos.Where(m=>m.Regla.Concepto!="PROVEEDOR"))PaymentLine(movement,null);
        }
        var xml=new XElement("ZEUS_SQL",document).ToString(SaveOptions.DisableFormatting);
        // El SP recibe varchar: las referencias numéricas conservan Unicode sin depender del codepage SQL.
        var ascii=new StringBuilder();
        foreach(var rune in xml.EnumerateRunes())
            if(rune.Value>127) ascii.Append("&#").Append(rune.Value).Append(';'); else ascii.Append(rune.ToString());
        return ascii.ToString();
    }
}
