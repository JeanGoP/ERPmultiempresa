using System.Xml.Linq;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Zeus;

static class TransferPostingTests
{
    private static ZeusSnapshot Snapshot(ZeusSnapshot template) => template with
    {
        Origen=template.Origen with { Factura="TR-00001", Total=119, Impuestos=0, Retenciones=0 },
        Traslado=new("01 Montelíbano","03 Caucasia","Traslado técnico de revisión"),
        Movimientos=
        [
            new(new("INVENTARIO_ORIGEN","143599",CentroCosto:"CC01"),-119),
            new(new("INVENTARIO_DESTINO","143599",CentroCosto:"CC03"),119)
        ]
    };

    public static void Unit(Action<bool,string> check,Action<Action,string> reject,ZeusSnapshot template)
    {
        var transfer=Snapshot(template);
        var key=Guid.NewGuid();
        var xml=ZeusXml.Build(transfer,key,transferIndicators:new Dictionary<string,string>{{"143599","4"}});
        var document=XElement.Parse(xml).Element("Documento")!;
        var header=document.Element("Document")!;
        var lines=document.Elements("Transac").ToArray();
        check(header.Element("FNTEDCTO")!.Value==transfer.Configuracion.Fuente
            && header.Element("DESCDCTO")!.Value.Contains("TRASLADO TR-00001 - 01 Montelíbano A 03 Caucasia")
            && header.Element("XmlAdicionales")!.Value==ZeusXml.Marker(key),"Traslado usa fuente configurada y marca de conciliación");
        check(lines.Select(l=>l.Element("VALORTRA")!.Value).SequenceEqual(["-119","119"])
            && lines.Select(l=>l.Element("IDCENCO")!.Value).SequenceEqual(["CC01","CC03"]),"Traslado acredita origen y debita destino con sus centros al mismo costo");
        check(header.Element("IDTERCERO")!.Value=="" && header.Element("IDCLIPRV")!.Value==""
            && lines.All(l=>l.Element("INDCPITRA")!.Value=="4" && new[]{"NITTRA","CLIPRV","TIPOFAC","NUMEFAC","VENCEFAC","Fechafact"}.All(field=>l.Element(field)!.Value=="")),"Traslado de inventario no genera tercero ni referencia de cartera");
        reject(()=>ZeusXml.Build(transfer with { Movimientos=[transfer.Movimientos[0],transfer.Movimientos[1] with { Valor=118 }] },key),"Traslado rechaza un asiento descuadrado");
        reject(()=>ZeusXml.Build(transfer with { Movimientos=[transfer.Movimientos[0],transfer.Movimientos[1] with { Base=119 }] },key),"Traslado rechaza bases tributarias");
    }

    public static async Task SqlAsync(Action<bool,string> check,ZeusTransport transport,SqlCommand query,ZeusSnapshot template)
    {
        var transfer=Snapshot(template);
        var key=Guid.NewGuid();
        var accepted=await transport.SendAsync(1,transfer,key,default);
        check(accepted.Estado=="CONTABILIZADO",$"El doble de Zeus confirma el traslado con sus centros: {accepted.Error}");
        check((await transport.SendAsync(1,transfer,key,default)).Estado=="CONTABILIZADO","Reintentar el traslado con la misma clave conserva el comprobante");
        query.CommandText="SELECT COUNT(*) FROM dbo.DOCUMENT";
        check(Convert.ToInt32(await query.ExecuteScalarAsync())==1,"El traslado queda contabilizado una sola vez");
        query.CommandText="DELETE dbo.TRANSAC;DELETE dbo.DOCUMENT;UPDATE dbo.TestMode SET Mode='WRONGCENTER'";
        await query.ExecuteNonQueryAsync();
        var wrongCenter=await transport.SendAsync(1,transfer,Guid.NewGuid(),default);
        query.CommandText="SELECT COUNT(*) FROM dbo.DOCUMENT";
        check(wrongCenter.Estado=="RECHAZADO"&&wrongCenter.Error!.Contains("centros de costo")
            && Convert.ToInt32(await query.ExecuteScalarAsync())==0,"Se revierte el comprobante si Zeus altera el centro de costo");
        query.CommandText="UPDATE dbo.TestMode SET Mode='OK'";
        await query.ExecuteNonQueryAsync();
        var missingCenter=transfer with { Movimientos=[transfer.Movimientos[0],transfer.Movimientos[1] with { Regla=transfer.Movimientos[1].Regla with { CentroCosto="" } }] };
        var rejected=await transport.SendAsync(1,missingCenter,Guid.NewGuid(),default);
        check(rejected.Estado=="RECHAZADO"&&rejected.Error!.Contains("Configura el centro de costo"),"La cuenta que exige centro de costo no admite un traslado sin configurarlo");
        var wrongSource=transfer with { Configuracion=transfer.Configuracion with { Fuente="99" } };
        var sourceRejected=await transport.SendAsync(1,wrongSource,Guid.NewGuid(),default);
        check(sourceRejected.Estado=="RECHAZADO"&&sourceRejected.Error!.Contains("fuente del traslado"),"El traslado exige una fuente habilitada en Zeus");
    }
}
