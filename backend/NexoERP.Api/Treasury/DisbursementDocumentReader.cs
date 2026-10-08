using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace NexoERP.Api.Treasury;

// Solo extracción para revisión humana; nunca crea asientos ni guarda el archivo.
public sealed class DisbursementDocumentReader(IConfiguration configuration)
{
    private const long MaxBytes=10*1024*1024;
    public async Task<object> ReadAsync(IFormFile file,CancellationToken ct)
    {
        if(file.Length is <8 or >MaxBytes)throw new ArgumentException("Adjunta un PDF, PNG o JPG de máximo 10 MB.");
        var extension=Path.GetExtension(file.FileName).ToLowerInvariant();
        if(extension is not(".pdf" or ".png" or ".jpg" or ".jpeg"))throw new ArgumentException("Solo se aceptan PDF, PNG y JPG.");
        var directory=Path.Combine(Path.GetTempPath(),"nexo-egreso-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var source=Path.Combine(directory,"documento"+extension);
            await using(var stream=new FileStream(source,FileMode.CreateNew,FileAccess.Write,FileShare.None))await file.CopyToAsync(stream,ct);
            await using(var stream=File.OpenRead(source))
            {
                var header=new byte[8];await stream.ReadExactlyAsync(header,ct);
                var valid=extension switch
                {
                    ".pdf"=>header.AsSpan(0,5).SequenceEqual("%PDF-"u8),
                    ".png"=>header.SequenceEqual(new byte[]{137,80,78,71,13,10,26,10}),
                    _=>header[0]==255&&header[1]==216&&header[2]==255
                };
                if(!valid)throw new ArgumentException("El contenido no corresponde al tipo de archivo seleccionado.");
            }
            string text;
            var method="OCR local";
            if(extension==".pdf")
            {
                var plain=Path.Combine(directory,"texto.txt");
                await RunAsync(configuration["Ocr:PdfToTextPath"]??"pdftotext",["-f","1","-l","3","-layout",source,plain],ct);
                text=File.Exists(plain)?await File.ReadAllTextAsync(plain,ct):"";
                if(text.Trim().Length>=40)method="Texto del PDF";
                else
                {
                    var prefix=Path.Combine(directory,"pagina");
                    await RunAsync(configuration["Ocr:PdfToPpmPath"]??"pdftoppm",["-f","1","-l","3","-scale-to","2000","-png",source,prefix],ct);
                    var pages=Directory.GetFiles(directory,"pagina-*.png").OrderBy(x=>x).Take(3).ToArray();
                    if(pages.Length==0)throw new ArgumentException("No se pudieron leer las primeras tres páginas del PDF.");
                    var output=new StringBuilder();
                    foreach(var page in pages)output.AppendLine(await OcrAsync(page,ct));
                    text=output.ToString();
                }
            }
            else text=await OcrAsync(source,ct);
            text=Regex.Replace(text,"[\\p{C}-[\\r\\n\\t]]","");
            if(text.Length>12000)text=text[..12000];
            if(text.Trim().Length<15)throw new ArgumentException("No se pudo leer suficiente texto. Prueba con una imagen más nítida o diligencia el egreso manualmente.");
            var lines=text.Split('\n',StringSplitOptions.TrimEntries|StringSplitOptions.RemoveEmptyEntries);
            var nit=Regex.Match(text,@"(?i)\b(?:NIT|CC|C\.C\.)\s*[:#-]?\s*(\d[\d.\- ]{5,16}\d)").Groups[1].Value;
            var invoice=Regex.Match(text,@"(?im)\b(?:factura|invoice|cuenta\s+de\s+cobro)\s*(?:de\s+venta\s*)?(?:n[oúm\.]*)?\s*[:#-]?\s*([A-Z0-9-]{3,25})").Groups[1].Value;
            var amount=Regex.Matches(text,@"(?im)\b(?:total(?:\s+a\s+pagar)?|valor\s+a\s+pagar)\s*[:$ ]+([\d.,]+)").Cast<Match>().Select(x=>x.Groups[1].Value).LastOrDefault()??"";
            var subject=lines.FirstOrDefault(x=>x.Length is >=5 and <=120&&!Regex.IsMatch(x,@"(?i)^(factura|nit|fecha|tel[eé]fono|direcci[oó]n|cliente|total)"))??"";
            return new{metodo=method,texto=text,proveedorSugerido=subject,identificacionSugerida=Regex.Replace(nit,"[^0-9]",""),facturaSugerida=invoice,totalSugerido=amount,
                advertencia="Datos sugeridos por lectura automática. Confirma proveedor, factura, concepto, cuenta contable y valor antes de contabilizar; el archivo no fue guardado."};
        }
        finally{try{Directory.Delete(directory,true);}catch(IOException){}catch(UnauthorizedAccessException){}}
    }
    private async Task<string> OcrAsync(string image,CancellationToken ct)
    {
        var executable=configuration["Ocr:TesseractPath"]??"tesseract";
        return await RunAsync(executable,[image,"stdout","-l","spa+eng","--psm","3"],ct);
    }
    private static async Task<string> RunAsync(string executable,string[] arguments,CancellationToken ct)
    {
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(ct);timeout.CancelAfter(TimeSpan.FromSeconds(30));
        using var process=new Process{StartInfo=new ProcessStartInfo(executable){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true}};
        foreach(var argument in arguments)process.StartInfo.ArgumentList.Add(argument);
        try
        {
            process.Start();
            var output=process.StandardOutput.ReadToEndAsync(timeout.Token);
            var errors=process.StandardError.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token);
            var value=await output;_ = await errors;
            if(process.ExitCode!=0)throw new ArgumentException("No se pudo leer el archivo con las herramientas locales de PDF/OCR. Revisa el archivo o la configuración del servidor.");
            return value;
        }
        catch(System.ComponentModel.Win32Exception){throw new ArgumentException("Faltan las herramientas locales de PDF/OCR en el servidor. Configura Poppler y Tesseract con español.");}
        catch(OperationCanceledException)when(!ct.IsCancellationRequested){try{process.Kill(true);}catch(InvalidOperationException){}throw new ArgumentException("La lectura excedió el tiempo permitido. Prueba con un archivo más pequeño.");}
        catch(OperationCanceledException){try{process.Kill(true);}catch(InvalidOperationException){}throw;}
    }
}
