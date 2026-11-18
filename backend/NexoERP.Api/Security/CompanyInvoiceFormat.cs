using System.Text.Json;

namespace NexoERP.Api.Security;

public sealed record CompanyInvoiceFormat(string? Direccion=null,string? Telefono=null,string? Ciudad=null,string? Leyenda=null)
{
    private static readonly JsonSerializerOptions JsonOptions=new(JsonSerializerDefaults.Web);

    public CompanyInvoiceFormat Normalize() => new(
        Clean(Direccion,300,"dirección"),Clean(Telefono,50,"teléfono"),Clean(Ciudad,100,"ciudad"),Clean(Leyenda,2000,"leyenda",true));

    public string ToJson() => JsonSerializer.Serialize(this,JsonOptions);

    public static CompanyInvoiceFormat? Read(string? json) => json is null
        ? null : JsonSerializer.Deserialize<CompanyInvoiceFormat>(json,JsonOptions);

    private static string? Clean(string? value,int maximum,string label,bool multiline=false)
    {
        value=value?.Trim();
        if(string.IsNullOrEmpty(value))return null;
        if(value.Length>maximum||value.Any(character=>char.IsControl(character)&&(!multiline||character is not ('\r' or '\n' or '\t'))))
            throw new ArgumentException($"Revisa {label} de impresión. Admite hasta {maximum} caracteres.");
        return value;
    }
}
