using System.Globalization;
using System.Xml;
using System.Xml.Linq;

namespace NexoERP.Api.Zeus;

public static class ZeusLineRounding
{
    private static XElement Read(string xml)
    {
        using var text=new StringReader(xml);
        using var reader=XmlReader.Create(text,new XmlReaderSettings{DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=30*1024*1024});
        return XElement.Load(reader);
    }
    private static XElement? Child(XElement e,string name)=>e.Elements().FirstOrDefault(x=>x.Name.LocalName==name);
    private static decimal Number(XElement? e)=>decimal.Parse(e?.Value??throw new FormatException(),NumberStyles.AllowDecimalPoint|NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture);
    public static bool Matches(string? xml,int lineNumber,decimal net,decimal gross,decimal discount,decimal charge)
    {
        if(string.IsNullOrWhiteSpace(xml)||discount<0||charge<0)return false;
        try
        {
            var root=Read(xml);
            if(root.Name.LocalName=="AttachedDocument")
                root=Read(root.Descendants().Where(e=>e.Name.LocalName=="Attachment")
                    .SelectMany(e=>e.Elements().Where(x=>x.Name.LocalName=="ExternalReference"))
                    .SelectMany(e=>e.Elements().Where(x=>x.Name.LocalName=="Description"))
                    .Select(e=>e.Value).First(v=>v.TrimStart().StartsWith("<")));
            if(root.Name.LocalName!="Invoice")return false;
            var matches=root.Elements().Where(e=>e.Name.LocalName=="InvoiceLine"&&int.TryParse(Child(e,"ID")?.Value,out var id)&&id==lineNumber).ToArray();
            if(matches.Length!=1)return false;
            var line=matches[0];var quantity=Number(Child(line,"InvoicedQuantity"));
            var priceNode=Child(Child(line,"Price")??throw new FormatException(),"PriceAmount");
            var price=Number(priceNode);
            if(quantity<=0||price<0||Number(Child(line,"LineExtensionAmount"))!=net
                ||decimal.Round(quantity*price,4,MidpointRounding.AwayFromZero)!=gross)return false;
            decimal xmlDiscount=0,xmlCharge=0;
            foreach(var allowance in line.Elements().Where(e=>e.Name.LocalName=="AllowanceCharge"))
            {
                var value=Number(Child(allowance,"Amount"));if(value<0)return false;
                var indicator=Child(allowance,"ChargeIndicator")?.Value.Trim();
                if(indicator is "true" or "1")xmlCharge+=value;
                else if(indicator is "false" or "0")xmlDiscount+=value;
                else return false;
            }
            if(xmlDiscount!=discount||xmlCharge!=charge)return false;
            // Ceros de formato (37177.00) no añaden precision a un precio entero.
            var fraction=(priceNode!.Value.Trim().Split('.').ElementAtOrDefault(1)??"").TrimEnd('0');
            decimal quantum=1;for(var i=0;i<fraction.Length;i++)quantum/=10;
            var margin=quantity*quantum/2+0.005m;
            return Math.Abs(net-(gross-discount+charge))<=margin;
        }
        catch(Exception e) when(e is XmlException or FormatException or OverflowException or InvalidOperationException){return false;}
    }
}
