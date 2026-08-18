SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'seg.fn_EmpresaAccess', N'IF') IS NULL
EXEC(N'
CREATE FUNCTION seg.fn_EmpresaAccess(@EmpresaId bigint)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS Permitido
    WHERE
        @EmpresaId = TRY_CONVERT(bigint, SESSION_CONTEXT(N''EmpresaId''))
        OR TRY_CONVERT(bit, SESSION_CONTEXT(N''BypassRls'')) = 1
);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'EmpresaSecurityPolicy' AND schema_id = SCHEMA_ID(N'seg'))
BEGIN
    EXEC sys.sp_set_session_context @key=N'BypassRls', @value=1;
    BEGIN TRANSACTION;

    CREATE SECURITY POLICY seg.EmpresaSecurityPolicy
        ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON ter.Tercero
        WITH (STATE = OFF, SCHEMABINDING = ON);

    DECLARE @Schema sysname;
    DECLARE @Table sysname;
    DECLARE @Sql nvarchar(max);

    DECLARE TenantTables CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.name, t.name
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        JOIN sys.columns c ON c.object_id = t.object_id AND c.name = N'EmpresaId'
        WHERE s.name IN (N'ter', N'inv', N'comp', N'cost', N'audit')
          AND NOT (s.name = N'ter' AND t.name = N'Tercero')
        ORDER BY s.name, t.name;

    OPEN TenantTables;
    FETCH NEXT FROM TenantTables INTO @Schema, @Table;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        RAISERROR('RLS filtro %s.%s', 10, 1, @Schema, @Table) WITH NOWAIT;
        SET @Sql = N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '
                 + QUOTENAME(@Schema) + N'.' + QUOTENAME(@Table) + N';';
        EXEC sys.sp_executesql @Sql;
        FETCH NEXT FROM TenantTables INTO @Schema, @Table;
    END;
    CLOSE TenantTables;
    DEALLOCATE TenantTables;

    -- Las escrituras cruzadas quedan bloqueadas incluso si una consulta omite EmpresaId.
    DECLARE BlockTables CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.name, t.name
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        JOIN sys.columns c ON c.object_id = t.object_id AND c.name = N'EmpresaId'
        WHERE s.name IN (N'ter', N'inv', N'comp', N'cost', N'audit')
        ORDER BY s.name, t.name;

    OPEN BlockTables;
    FETCH NEXT FROM BlockTables INTO @Schema, @Table;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        RAISERROR('RLS bloqueo %s.%s', 10, 1, @Schema, @Table) WITH NOWAIT;
        SET @Sql = N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '
                 + QUOTENAME(@Schema) + N'.' + QUOTENAME(@Table) + N' AFTER INSERT;';
        EXEC sys.sp_executesql @Sql;
        SET @Sql = N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON '
                 + QUOTENAME(@Schema) + N'.' + QUOTENAME(@Table) + N' AFTER UPDATE;';
        EXEC sys.sp_executesql @Sql;
        FETCH NEXT FROM BlockTables INTO @Schema, @Table;
    END;
    CLOSE BlockTables;
    DEALLOCATE BlockTables;

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy WITH (STATE = ON);');

    INSERT core.SchemaMigration(MigrationId, Descripcion)
    VALUES ('005_tenant_security', N'Aislamiento multiempresa mediante Row-Level Security y predicados de bloqueo');

    COMMIT TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls', @value=NULL;
END;
GO
