namespace NexoERP.Api.Inventory;

internal static class InventoryAvailability
{
    // Uses the article (a), warehouse (b), and posted balance (s) of the caller.
    internal const string JoinSql = """
        OUTER APPLY (
            SELECT SUM(o.CantidadDisponible) AS Cantidad
            FROM inv.SaldoOrigenBodega o
            WHERE o.EmpresaId=a.EmpresaId AND o.ArticuloId=a.ArticuloId AND o.BodegaId=b.BodegaId
        ) origin
        OUTER APPLY (
            SELECT COUNT_BIG(*) AS Cantidad
            FROM inv.UnidadSerializada u
            WHERE a.ManejaSerial=1 AND u.EmpresaId=a.EmpresaId AND u.ArticuloId=a.ArticuloId
              AND u.BodegaActualId=b.BodegaId AND u.Estado='DISPONIBLE'
        ) units
        CROSS APPLY (
            SELECT CAST(CASE WHEN a.Activo=0 OR b.Activa=0 OR ISNULL(s.Existencia,0)<=0 THEN 0
                ELSE (SELECT MIN(v.Cantidad) FROM (VALUES
                    (s.Existencia), (ISNULL(origin.Cantidad,0)),
                    (CASE WHEN a.ManejaSerial=1 THEN units.Cantidad ELSE s.Existencia END)
                ) v(Cantidad)) END AS decimal(20,6)) AS Disponible
        ) availability
        """;
}
