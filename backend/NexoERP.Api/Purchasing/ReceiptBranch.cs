using System.Data;
using Microsoft.Data.SqlClient;
using NexoERP.Api.Zeus;

namespace NexoERP.Api.Purchasing;

public static class ReceiptBranch
{
 public static async Task<(long Id,string Name)> ResolveAsync(SqlConnection c,SqlTransaction tx,long company,long receipt,long? requested,CancellationToken ct)
 {
  await using var q=ZeusRepository.Command(c,"SELECT r.SucursalId,s.Nombre FROM inv.RecepcionMercancia r WITH(UPDLOCK,HOLDLOCK) LEFT JOIN core.Sucursal s ON s.EmpresaId=r.EmpresaId AND s.SucursalId=r.SucursalId WHERE r.EmpresaId=@E AND r.RecepcionMercanciaId=@R",company,tx);ZeusRepository.Add(q,"@R",receipt);
  await using(var r=await q.ExecuteReaderAsync(ct))
  {
   if(!await r.ReadAsync(ct))throw new ArgumentException("Entrada no encontrada en esta empresa.");
   if(!r.IsDBNull(0))
   {
    if(requested.HasValue&&requested!=r.GetInt64(0))throw new ArgumentException("La entrada ya tiene una sucursal contable y no puede cambiarse.");
    return(r.GetInt64(0),r.GetString(1));
   }
  }
  q.CommandText="""
   SELECT DISTINCT b.SucursalId,s.Nombre,s.Activa
   FROM inv.RecepcionMercancia r JOIN inv.RecepcionMercanciaLinea l ON l.EmpresaId=r.EmpresaId AND l.RecepcionMercanciaId=r.RecepcionMercanciaId
   LEFT JOIN inv.Bodega b WITH(HOLDLOCK) ON b.EmpresaId=l.EmpresaId AND b.BodegaId=COALESCE(l.BodegaId,r.BodegaId)
   LEFT JOIN core.Sucursal s WITH(HOLDLOCK) ON s.EmpresaId=b.EmpresaId AND s.SucursalId=b.SucursalId
   WHERE r.EmpresaId=@E AND r.RecepcionMercanciaId=@R;
   """;
  var branches=new Dictionary<long,string>();
  await using(var r=await q.ExecuteReaderAsync(ct))while(await r.ReadAsync(ct))
  {
   if(r.IsDBNull(0)||r.IsDBNull(1)||!r.GetBoolean(2))throw new ArgumentException("Asigna una sucursal activa a cada bodega de la entrada en Datos maestros → Bodegas.");
   branches[r.GetInt64(0)]=r.GetString(1);
  }
  if(branches.Count==0)throw new ArgumentException("La entrada no tiene bodegas para determinar su sucursal.");
  var selected=requested??(branches.Count==1?branches.Keys.Single():throw new ArgumentException("La entrada incluye varias sucursales. Selecciona la sucursal que registra el comprobante."));
  if(!branches.ContainsKey(selected))throw new ArgumentException("La sucursal contable debe ser una de las sucursales de las bodegas de esta entrada.");
  return(selected,branches[selected]);
 }
 public static async Task SaveAsync(SqlConnection c,SqlTransaction tx,long company,long receipt,long branch,long user,CancellationToken ct)
 {
  await using var q=ZeusRepository.Command(c,"""
   UPDATE inv.RecepcionMercancia SET SucursalId=@B WHERE EmpresaId=@E AND RecepcionMercanciaId=@R AND SucursalId IS NULL;
   IF @@ROWCOUNT=1 INSERT audit.Evento(EmpresaId,UsuarioId,Operacion,Entidad,EntidadId,ValoresPosteriores,AplicacionOrigen)
   VALUES(@E,@U,'ENTRADA_SUCURSAL','inv.RecepcionMercancia',CONVERT(nvarchar(100),@R),(SELECT @B sucursalId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'ERP');
   """,company,tx);
  ZeusRepository.Add(q,"@R",receipt);ZeusRepository.Add(q,"@B",branch);ZeusRepository.Add(q,"@U",user);await q.ExecuteNonQueryAsync(ct);
 }
}
