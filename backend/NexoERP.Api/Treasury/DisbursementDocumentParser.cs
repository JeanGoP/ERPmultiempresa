using System.Globalization;
using System.Text.RegularExpressions;

namespace NexoERP.Api.Treasury;

public sealed record DisbursementAmount(string Concepto, decimal Valor);

public sealed record DisbursementDocumentExtraction(
    string Metodo,
    string Texto,
    string ProveedorSugerido,
    string IdentificacionSugerida,
    string FacturaSugerida,
    string FechaSugerida,
    string TotalSugerido,
    decimal? TotalSugeridoNumero,
    IReadOnlyList<DisbursementAmount> Importes,
    string Advertencia);

public static partial class DisbursementDocumentParser
{
    private const decimal MaxAmount = 1_000_000_000_000m;

    [GeneratedRegex(@"\b(?:total\s+(?:de\s+)?retenci[oó]n(?:es)?|retenci[oó]n(?:es)?|rete(?:fuente|iva|ica)|total\s+(?:de\s+)?impuestos?|iva|impuestos?|descuentos?|subtotal(?:\s+neto)?|base\s+gravable|otros\s+cargos|fletes?|valor\s+total\s+a\s+pagar|total\s+a\s+pagar|neto\s+a\s+pagar|valor\s+a\s+pagar|valor\s+pagado|importe\s+total|valor\s+total|valor\s+neto|total(?:\s+(?:factura|documento))?|saldo\s+pendiente)\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex AmountLabel();

    [GeneratedRegex(@"(?<!\d)(?:\$\s*|(?:COP|USD|EUR)\s*)?\(?-?\d[\d.,\s]*\d\)?(?!\d)|(?<!\d)(?:\$\s*|(?:COP|USD|EUR)\s*)?\(?-?\d\)?(?!\d)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex NumberToken();

    public static DisbursementDocumentExtraction Parse(string source, string method)
    {
        var text=Regex.Replace(source,"[\\p{C}-[\\r\\n\\t]]","");
        var lines=text.Split('\n',StringSplitOptions.TrimEntries|StringSplitOptions.RemoveEmptyEntries);
        var amounts=new List<DisbursementAmount>();
        var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for(var i=0;i<lines.Length;i++)
        {
            var line=lines[i];
            var labels=AmountLabel().Matches(line);
            for(var j=0;j<labels.Count;j++)
            {
                var label=labels[j].Value.Trim();
                var end=j+1<labels.Count?labels[j+1].Index:line.Length;
                var valueText=line[(labels[j].Index+labels[j].Length)..end];
                if(!TryFindAmount(valueText,out var amount)&&j==labels.Count-1&&i+1<lines.Length&&AmountLabel().Matches(lines[i+1]).Count==0)
                    TryFindAmount(lines[i+1],out amount);
                if(amount<=0||amount>MaxAmount)continue;
                var kind=NormalizeLabel(label);
                if(seen.Add($"{kind}:{amount.ToString(CultureInfo.InvariantCulture)}"))amounts.Add(new(kind,amount));
            }
        }
        // También se muestran importes con símbolo monetario que el formato no rotula.
        // No se toman fechas, porcentajes ni números de documento sin moneda.
        var knownValues=amounts.Select(x=>x.Valor).ToHashSet();
        foreach(Match match in Regex.Matches(text,@"(?i)(?:\$\s*|\b(?:COP|USD|EUR)\s+)-?\d[\d., ]*"))
            if(TryFindAmount(match.Value,out var amount)&&amount>0&&amount<=MaxAmount&&knownValues.Add(amount))
                amounts.Add(new("Otro importe del soporte",amount));

        var preferred=amounts.Where(x=>x.Concepto is "Total a pagar" or "Valor pagado" or "Total").ToArray();
        var distinct=preferred.Select(x=>x.Valor).Distinct().ToArray();
        var suggested=distinct.Length==1?(decimal?)distinct[0]:null;
        var nit=Regex.Match(text,@"(?i)\b(?:NIT|CC|C\.C\.)\s*[:#-]?\s*(\d[\d.\- ]{5,16}\d)").Groups[1].Value;
        var invoice=Regex.Match(text,@"(?im)\b(?:factura|invoice|cuenta\s+de\s+cobro)\s*(?:(?:electr[oó]nica\s*)?(?:de\s+venta\s*)?)?(?:n[oúmmero°\.]*\s*)?[:#-]?\s*([A-Z0-9][A-Z0-9-]{2,24})\b").Groups[1].Value;
        var date=Regex.Match(text,@"(?im)\bfecha(?:\s+de\s+(?:emisi[oó]n|expedici[oó]n|pago))?\s*[:#-]?\s*(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{4})\b").Groups[1].Value;
        var subject=lines.FirstOrDefault(x=>x.Length is >=5 and <=120&&!Regex.IsMatch(x,@"(?i)^(factura|nit|fecha|tel[eé]fono|direcci[oó]n|cliente|total|comprobante|recibo|documento|p[aá]gina)\b"))??"";
        var preview=text.Length>12000?text[..6000]+"\n[…]\n"+text[^6000..]:text;
        return new(method,preview,subject,Regex.Replace(nit,"[^0-9]",""),invoice,date,
            suggested?.ToString("0.00",CultureInfo.InvariantCulture)??"",suggested,amounts.Take(30).ToArray(),
            "Datos sugeridos por lectura automática. Confirma beneficiario, factura, concepto, cuenta contable y valor antes de contabilizar; el archivo no fue guardado.");
    }

    private static string NormalizeLabel(string label)
    {
        var normalized=label.ToLowerInvariant();
        if(normalized.Contains("retenc")||normalized.Contains("rete"))return "Retenciones";
        if(normalized.Contains("iva")||normalized.Contains("impuesto"))return "Impuestos / IVA";
        if(normalized.Contains("descuento"))return "Descuentos";
        if(normalized.Contains("subtotal"))return "Subtotal";
        if(normalized.Contains("base gravable"))return "Base gravable";
        if(normalized.Contains("cargos"))return "Otros cargos";
        if(normalized.Contains("flete"))return "Fletes";
        if(normalized.Contains("pagado"))return "Valor pagado";
        if(normalized.Contains("a pagar"))return "Total a pagar";
        if(normalized.Contains("neto"))return "Valor neto";
        if(normalized.Contains("saldo"))return "Saldo pendiente";
        return "Total";
    }

    private static bool TryFindAmount(string valueText,out decimal amount)
    {
        amount=0;
        // Se exige un separador o moneda cuando hay texto libre para no tomar números de factura o fechas.
        var trimmed=valueText.TrimStart(' ',':','=','$','\t');
        var match=NumberToken().Matches(trimmed).Cast<Match>().FirstOrDefault(x=>
            x.Index<=Math.Min(16,trimmed.Length)&&
            (x.Index+x.Length>=trimmed.Length||trimmed[x.Index+x.Length]!='%')&&
            !Regex.IsMatch(x.Value,@"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"));
        if(match is null)return false;
        var token=Regex.Replace(match.Value,@"(?i)[^\d.,]","");
        if(token.Length==0)return false;
        var comma=token.LastIndexOf(',');var dot=token.LastIndexOf('.');
        var separator=Math.Max(comma,dot);
        var decimalDigits=separator>=0?token.Length-separator-1:0;
        var decimalSeparator=separator>=0&&decimalDigits is 1 or 2;
        var digits=Regex.Replace(token,"[^0-9]","");
        if(digits.Length==0||digits.Length>15)return false;
        if(decimalSeparator)digits=digits.Insert(digits.Length-decimalDigits,".");
        return decimal.TryParse(digits,NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out amount);
    }
}
