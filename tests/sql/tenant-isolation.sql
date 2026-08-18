SET NOCOUNT ON;
SET XACT_ABORT ON;

EXEC sys.sp_set_session_context @key=N'BypassRls', @value=1;
BEGIN TRANSACTION;

DECLARE @EmpresaA bigint;
DECLARE @EmpresaB bigint;
DECLARE @UnidadA bigint;
DECLARE @UnidadB bigint;
DECLARE @Suffix varchar(12) = RIGHT(REPLACE(CONVERT(varchar(36), NEWID()), '-', ''), 12);

INSERT core.Empresa(Codigo, Nit, RazonSocial) VALUES (CONCAT('RLS-A-',@Suffix), CONCAT('8',RIGHT(@Suffix,9)), N'Empresa RLS A');
SET @EmpresaA = SCOPE_IDENTITY();
INSERT core.Empresa(Codigo, Nit, RazonSocial) VALUES (CONCAT('RLS-B-',@Suffix), CONCAT('7',RIGHT(@Suffix,9)), N'Empresa RLS B');
SET @EmpresaB = SCOPE_IDENTITY();

INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES (@EmpresaA,'UND',N'Unidad A','und');
SET @UnidadA = SCOPE_IDENTITY();
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES (@EmpresaB,'UND',N'Unidad B','und');
SET @UnidadB = SCOPE_IDENTITY();

EXEC sys.sp_set_session_context @key=N'BypassRls', @value=NULL;
EXEC sys.sp_set_session_context @key=N'EmpresaId', @value=@EmpresaA;

IF (SELECT COUNT(*) FROM inv.UnidadMedida) <> 1
    THROW 51910, 'RLS permitió leer datos de otra empresa.', 1;
IF NOT EXISTS (SELECT 1 FROM inv.UnidadMedida WHERE UnidadMedidaId=@UnidadA)
    THROW 51911, 'RLS ocultó los datos de la empresa activa.', 1;

BEGIN TRY
    INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES (@EmpresaB,'ILEGAL',N'Cruce no permitido');
    THROW 51912, 'RLS permitió escribir en otra empresa.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51912 THROW;
END CATCH;

EXEC sys.sp_set_session_context @key=N'BypassRls', @value=1;
EXEC sys.sp_set_session_context @key=N'EmpresaId', @value=NULL;
ROLLBACK TRANSACTION;
EXEC sys.sp_set_session_context @key=N'BypassRls', @value=NULL;

PRINT 'QA multiempresa correcto: lectura filtrada y escritura cruzada bloqueada.';
