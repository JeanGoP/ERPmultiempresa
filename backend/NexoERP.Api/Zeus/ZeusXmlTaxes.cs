using System.Globalization;
using System.Xml;
using System.Xml.Linq;

namespace NexoERP.Api.Zeus;

public static class ZeusXmlTaxes
{
    private static XElement Read(string xml)
    {
        using var text=new StringReader(xml);
        using var reader=XmlReader.Create(text,new XmlReaderSettings{DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=30*1024*1024});
        return XElement.Load(reader);
    }
    private static string Value(XElement parent,string name)=>parent.Elements().FirstOrDefault(e=>e.Name.LocalName==name)?.Value.Trim()??"";
    private static decimal Number(string value)=>decimal.TryParse(value,NumberStyles.AllowDecimalPoint|NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture,out var n)?n:throw new ArgumentException("El XML no contiene una base, tarifa o valor de impuesto válido para Zeus.");
    public static ZeusPreviewRequest Parse(string? xml,IReadOnlyDictionary<string,long?> warehouses,decimal savedRetention)
    {
        if(string.IsNullOrWhiteSpace(xml))throw new ArgumentException("No hay XML guardado para obtener el desglose contable. La entrada ERP se conserva; requiere revisión de integración.");
        XElement root;
        try
        {
            root=Read(xml);
            if(root.Name.LocalName=="AttachedDocument")
            {
                var embedded=root.Descendants().Where(e=>e.Name.LocalName=="Attachment").SelectMany(a=>a.Elements().Where(e=>e.Name.LocalName=="ExternalReference")).SelectMany(e=>e.Elements().Where(x=>x.Name.LocalName=="Description")).Select(e=>e.Value).FirstOrDefault(v=>v.TrimStart().StartsWith("<"));
                root=Read(embedded??throw new ArgumentException("El contenedor XML no incluye la factura original."));
            }
        }
        catch(XmlException){throw new ArgumentException("El XML guardado no se puede interpretar para Zeus.");}
        if(root.Name.LocalName!="Invoice")throw new ArgumentException("La contabilización automática requiere un XML de factura Invoice.");
        List<ZeusTax> Extract(XElement node,bool withholding,long? warehouse)
        {
            var result=new List<ZeusTax>();
            foreach(var total in node.Elements().Where(e=>e.Name.LocalName is "TaxTotal" or "WithholdingTaxTotal"))
            {
                var subs=total.Elements().Where(e=>e.Name.LocalName=="TaxSubtotal").ToArray();
                if(subs.Length==0&&Number(Value(total,"TaxAmount"))!=0)throw new ArgumentException("El XML tiene impuestos sin desglose; no se inventan conceptos ni tarifas.");
                foreach(var sub in subs)
                {
                    var category=sub.Elements().FirstOrDefault(e=>e.Name.LocalName=="TaxCategory")??sub;
                    var scheme=category.Elements().FirstOrDefault(e=>e.Name.LocalName=="TaxScheme")??category;
                    var code=Value(scheme,"ID");var name=Value(scheme,"Name").ToLowerInvariant().Replace(" ","");
                    if(name.Contains("autoret")||name.Contains("autorret")||name.Contains("selfwithhold"))continue;
                    var retained=total.Name.LocalName=="WithholdingTaxTotal"||code is "05" or "06" or "07";
                    if(retained!=withholding)continue;
                    var amount=Number(Value(sub,"TaxAmount"));if(amount==0)continue;
                    var concept=code switch{"01"=>"IVA","05"=>"RETEIVA","06"=>"RETEFUENTE","07"=>"RETEICA","03" or "04"=>"OTRO_IMPUESTO",_=>throw new ArgumentException($"El impuesto XML {code} no tiene un concepto Zeus compatible.")};
                    if(retained&&concept is not ("RETEIVA" or "RETEFUENTE" or "RETEICA"))throw new ArgumentException("El concepto de retención XML es ambiguo.");
                    var basis=Number(Value(sub,"TaxableAmount"));if(basis<=0)throw new ArgumentException("El XML no informa una base positiva del impuesto.");
                    var percent=Value(category,"Percent");
                    var rate=percent.Length>0?Number(percent):decimal.Round(amount*100/basis,4,MidpointRounding.AwayFromZero);
                    result.Add(new(concept,rate,basis,amount,concept=="IVA"?warehouse:null));
                }
            }
            return result;
        }
        var lines=root.Elements().Where(e=>e.Name.LocalName=="InvoiceLine").ToArray();
        var taxes=new List<ZeusTax>();var retentions=new List<ZeusTax>();
        foreach(var line in lines)
        {
            var id=Value(line,"ID");if(long.TryParse(id,NumberStyles.None,CultureInfo.InvariantCulture,out var lineNumber))id=lineNumber.ToString(CultureInfo.InvariantCulture);
            if(!warehouses.TryGetValue(id,out var warehouse))throw new ArgumentException("Las líneas del XML no coinciden con las líneas guardadas de la entrada.");
            taxes.AddRange(Extract(line,false,warehouse));retentions.AddRange(Extract(line,true,null));
        }
        if(taxes.Count==0)taxes=Extract(root,false,null);
        var headerRetentions=Extract(root,true,null);if(headerRetentions.Count>0)retentions=headerRetentions;
        if(savedRetention==0)retentions.Clear();
        if(ZeusTaxRounding.Money(retentions.Sum(t=>t.Valor))!=savedRetention&&retentions.Sum(t=>ZeusTaxRounding.Money(t.Valor))!=savedRetention)
            throw new ArgumentException("La retención guardada fue ajustada o no tiene desglose en el XML. Revisa la configuración fiscal antes de enviar a Zeus; no se modifica el valor del ERP.");
        // La normalización monetaria se realiza en ZeusJournal con los totales ERP.
        return new(taxes.ToArray(),retentions.ToArray());
    }
}
