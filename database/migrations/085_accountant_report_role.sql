SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='085_accountant_report_role')
BEGIN
    IF NOT EXISTS(SELECT 1 FROM seg.Rol WHERE Codigo='CONTADOR')
        INSERT seg.Rol(Codigo,Nombre) VALUES('CONTADOR',N'Contador - consulta de informes');
    INSERT seg.RolPermiso(RolId,PermisoId)
    SELECT r.RolId,p.PermisoId FROM seg.Rol r CROSS JOIN seg.Permiso p
    WHERE r.Codigo='CONTADOR' AND p.Codigo='CONTABILIDAD.INFORMES.CONSULTAR'
      AND NOT EXISTS(SELECT 1 FROM seg.RolPermiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
    INSERT core.SchemaMigration(MigrationId,Descripcion)
    VALUES('085_accountant_report_role',N'Rol de consulta contable para asignar informes sin permisos de contabilización');
END;
COMMIT;
GO
