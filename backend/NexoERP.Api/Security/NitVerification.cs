namespace NexoERP.Api.Security;

public static class NitVerification
{
    private static readonly int[] Weights=[3,7,13,17,19,23,29,37,41,43,47,53,59,67,71];

    public static string? Calculate(string? nit)
    {
        var digits=nit?.Trim();
        if(string.IsNullOrEmpty(digits)||digits.Length>Weights.Length||digits.Any(c=>c<'0'||c>'9'))return null;
        var sum=0;
        for(var i=0;i<digits.Length;i++)sum+=(digits[digits.Length-1-i]-'0')*Weights[i];
        var remainder=sum%11;
        return (remainder<2?remainder:11-remainder).ToString();
    }
}
