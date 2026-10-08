using System.Diagnostics;
using System.Text;

namespace NexoERP.Api.Treasury;

// Solo extracción para revisión humana; nunca crea asientos ni guarda el archivo.
public sealed class DisbursementDocumentReader(IConfiguration configuration)
{
    private const long MaxBytes=10*1024*1024;
    private const int MaxOcrPages=12;
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
                // El total puede estar en la última página; el texto embebido se lee completo.
                await RunAsync(configuration["Ocr:PdfToTextPath"]??"pdftotext",["-layout",source,plain],ct);
                text=File.Exists(plain)?await File.ReadAllTextAsync(plain,ct):"";
                var textPages=text.Split('\f').Where(x=>!string.IsNullOrWhiteSpace(x)).ToArray();
                var extracted=DisbursementDocumentParser.Parse(text,"Texto del PDF");
                // Un PDF mixto puede contener texto en unas páginas e imágenes en otras.
                var needsOcr=text.Trim().Length<80||extracted.Importes.Count<2||textPages.Any(x=>x.Trim().Length<40);
                if(!needsOcr)method="Texto del PDF";
                else
                {
                    if(textPages.Length>MaxOcrPages)
                        throw new ArgumentException($"El PDF requiere OCR en más de {MaxOcrPages} páginas. Divídelo en archivos más pequeños o diligencia el egreso manualmente.");
                    var prefix=Path.Combine(directory,"pagina");
                    await RunAsync(configuration["Ocr:PdfToPpmPath"]??"pdftoppm",["-f","1","-l",MaxOcrPages.ToString(),"-scale-to","2000","-png",source,prefix],ct);
                    var pages=Directory.GetFiles(directory,"pagina-*.png").OrderBy(x=>x).ToArray();
                    if(pages.Length==0)throw new ArgumentException("No se pudieron leer las páginas del PDF.");
                    var output=new StringBuilder();
                    foreach(var page in pages)output.AppendLine(await OcrAsync(page,ct));
                    method=string.IsNullOrWhiteSpace(text)?"OCR local":"Texto del PDF + OCR local";
                    text=string.IsNullOrWhiteSpace(text)?output.ToString():text+"\n"+output;
                }
            }
            else text=await OcrAsync(source,ct);
            if(text.Trim().Length<15)throw new ArgumentException("No se pudo leer suficiente texto. Prueba con una imagen más nítida o diligencia el egreso manualmente.");
            return DisbursementDocumentParser.Parse(text,method);
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
