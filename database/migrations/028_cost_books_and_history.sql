SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='028_cost_books_and_history')
BEGIN
    BEGIN TRANSACTION;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
    CREATE TABLE inv.GrupoInventario
    (
        GrupoInventarioId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        Codigo nvarchar(30) NOT NULL,
        Nombre nvarchar(120) NOT NULL,
        NaturalezaUso nvarchar(120) NOT NULL,
        Activo bit NOT NULL CONSTRAINT DF_GrupoInventario_Activo DEFAULT 1,
        CONSTRAINT PK_GrupoInventario PRIMARY KEY CLUSTERED(GrupoInventarioId),
        CONSTRAINT UQ_GrupoInventario_EmpresaId UNIQUE(EmpresaId,GrupoInventarioId),
        CONSTRAINT UQ_GrupoInventario_Codigo UNIQUE(EmpresaId,Codigo),
        CONSTRAINT FK_GrupoInventario_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId)
    );
    ALTER TABLE inv.Articulo ADD GrupoInventarioId bigint NULL;
    EXEC(N'ALTER TABLE inv.Articulo ADD CONSTRAINT FK_Articulo_GrupoInventario FOREIGN KEY(EmpresaId,GrupoInventarioId) REFERENCES inv.GrupoInventario(EmpresaId,GrupoInventarioId);');
    CREATE TABLE cost.LibroCosto
    (
        LibroCostoId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        Codigo nvarchar(30) NOT NULL,
        Nombre nvarchar(120) NOT NULL,
        Categoria varchar(15) NOT NULL,
        FormulaValoracion varchar(30) NOT NULL,
        EsPrincipal bit NOT NULL CONSTRAINT DF_LibroCosto_Principal DEFAULT 0,
        Estado varchar(15) NOT NULL CONSTRAINT DF_LibroCosto_Estado DEFAULT 'CONFIGURACION',
        CreadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_LibroCosto_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_LibroCosto PRIMARY KEY CLUSTERED(LibroCostoId),
        CONSTRAINT UQ_LibroCosto_EmpresaId UNIQUE(EmpresaId,LibroCostoId),
        CONSTRAINT UQ_LibroCosto_Codigo UNIQUE(EmpresaId,Codigo),
        CONSTRAINT FK_LibroCosto_Empresa FOREIGN KEY(EmpresaId) REFERENCES core.Empresa(EmpresaId),
        CONSTRAINT CK_LibroCosto_Categoria CHECK(Categoria IN('OPERATIVO','CONTABLE','FISCAL','GERENCIAL','COMERCIAL')),
        CONSTRAINT CK_LibroCosto_Formula CHECK(FormulaValoracion IN('PROMEDIO_MOVIL','PROMEDIO_PERIODICO','PEPS','IDENTIFICACION_ESPECIFICA')),
        CONSTRAINT CK_LibroCosto_Estado CHECK(Estado IN('CONFIGURACION','ACTIVO','INACTIVO'))
    );
    CREATE UNIQUE INDEX UX_LibroCosto_Principal ON cost.LibroCosto(EmpresaId) WHERE EsPrincipal=1 AND Estado='ACTIVO';
    CREATE TABLE cost.PoliticaValoracionGrupo
    (
        PoliticaValoracionGrupoId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        LibroCostoId bigint NOT NULL,
        GrupoInventarioId bigint NOT NULL,
        FormulaValoracion varchar(30) NOT NULL,
        VigenteDesde date NOT NULL,
        VigenteHasta date NULL,
        MotivoCambio nvarchar(500) NULL,
        AprobadoPorUsuarioId bigint NULL,
        CONSTRAINT PK_PoliticaValoracionGrupo PRIMARY KEY CLUSTERED(PoliticaValoracionGrupoId),
        CONSTRAINT UQ_PoliticaValoracionGrupo UNIQUE(EmpresaId,LibroCostoId,GrupoInventarioId,VigenteDesde),
        CONSTRAINT FK_PoliticaValoracionGrupo_Libro FOREIGN KEY(EmpresaId,LibroCostoId) REFERENCES cost.LibroCosto(EmpresaId,LibroCostoId),
        CONSTRAINT FK_PoliticaValoracionGrupo_Grupo FOREIGN KEY(EmpresaId,GrupoInventarioId) REFERENCES inv.GrupoInventario(EmpresaId,GrupoInventarioId),
        CONSTRAINT FK_PoliticaValoracionGrupo_Usuario FOREIGN KEY(AprobadoPorUsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_PoliticaValoracionGrupo_Formula CHECK(FormulaValoracion IN('PROMEDIO_MOVIL','PROMEDIO_PERIODICO','PEPS','IDENTIFICACION_ESPECIFICA')),
        CONSTRAINT CK_PoliticaValoracionGrupo_Fechas CHECK(VigenteHasta IS NULL OR VigenteHasta>=VigenteDesde)
    );
    CREATE TABLE cost.MovimientoCostoLibro
    (
        MovimientoCostoLibroId bigint IDENTITY(1,1) NOT NULL,
        EmpresaId bigint NOT NULL,
        LibroCostoId bigint NOT NULL,
        MovimientoInventarioId bigint NOT NULL,
        CostoUnitarioAnterior decimal(20,8) NOT NULL,
        CostoUnitarioMovimiento decimal(20,8) NOT NULL,
        CostoUnitarioPosterior decimal(20,8) NOT NULL,
        ValorMovimiento decimal(20,4) NOT NULL,
        ValorTotalPosterior decimal(20,4) NOT NULL,
        CONSTRAINT PK_MovimientoCostoLibro PRIMARY KEY CLUSTERED(MovimientoCostoLibroId),
        CONSTRAINT UQ_MovimientoCostoLibro UNIQUE(EmpresaId,LibroCostoId,MovimientoInventarioId),
        CONSTRAINT FK_MovimientoCostoLibro_Libro FOREIGN KEY(EmpresaId,LibroCostoId) REFERENCES cost.LibroCosto(EmpresaId,LibroCostoId),
        CONSTRAINT FK_MovimientoCostoLibro_Movimiento FOREIGN KEY(EmpresaId,MovimientoInventarioId) REFERENCES inv.MovimientoInventario(EmpresaId,MovimientoInventarioId)
    );
    CREATE TABLE cost.SaldoCostoLibroBodega
    (
        EmpresaId bigint NOT NULL,
        LibroCostoId bigint NOT NULL,
        BodegaId bigint NOT NULL,
        ArticuloId bigint NOT NULL,
        Existencia decimal(20,6) NOT NULL,
        CostoUnitario decimal(20,8) NOT NULL,
        ValorTotal decimal(20,4) NOT NULL,
        UltimoMovimientoCostoLibroId bigint NULL,
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_SaldoCostoLibroBodega PRIMARY KEY CLUSTERED(EmpresaId,LibroCostoId,BodegaId,ArticuloId),
        CONSTRAINT FK_SaldoCostoLibroBodega_Libro FOREIGN KEY(EmpresaId,LibroCostoId) REFERENCES cost.LibroCosto(EmpresaId,LibroCostoId),
        CONSTRAINT FK_SaldoCostoLibroBodega_Bodega FOREIGN KEY(EmpresaId,BodegaId) REFERENCES inv.Bodega(EmpresaId,BodegaId),
        CONSTRAINT FK_SaldoCostoLibroBodega_Articulo FOREIGN KEY(EmpresaId,ArticuloId) REFERENCES inv.Articulo(EmpresaId,ArticuloId),
        CONSTRAINT CK_SaldoCostoLibroBodega_Valores CHECK(CostoUnitario>=0 AND ValorTotal>=0)
    );

    INSERT cost.LibroCosto(EmpresaId,Codigo,Nombre,Categoria,FormulaValoracion,EsPrincipal,Estado)
    SELECT EmpresaId,'OPERATIVO',N'Costo operativo principal','OPERATIVO','PROMEDIO_MOVIL',1,'ACTIVO' FROM core.Empresa;
    INSERT cost.MovimientoCostoLibro(EmpresaId,LibroCostoId,MovimientoInventarioId,CostoUnitarioAnterior,CostoUnitarioMovimiento,CostoUnitarioPosterior,ValorMovimiento,ValorTotalPosterior)
    SELECT m.EmpresaId,l.LibroCostoId,m.MovimientoInventarioId,m.CostoUnitarioAnterior,m.CostoUnitarioMovimiento,m.CostoPromedioPosterior,m.ValorMovimiento,m.ValorTotalPosterior
    FROM inv.MovimientoInventario m JOIN cost.LibroCosto l ON l.EmpresaId=m.EmpresaId AND l.EsPrincipal=1 AND l.Estado='ACTIVO';
    INSERT cost.SaldoCostoLibroBodega(EmpresaId,LibroCostoId,BodegaId,ArticuloId,Existencia,CostoUnitario,ValorTotal,UltimoMovimientoCostoLibroId)
    SELECT s.EmpresaId,l.LibroCostoId,s.BodegaId,s.ArticuloId,s.Existencia,s.CostoPromedio,s.ValorTotal,mc.MovimientoCostoLibroId
    FROM inv.SaldoArticuloBodega s JOIN cost.LibroCosto l ON l.EmpresaId=s.EmpresaId AND l.EsPrincipal=1 AND l.Estado='ACTIVO'
    LEFT JOIN cost.MovimientoCostoLibro mc ON mc.EmpresaId=s.EmpresaId AND mc.LibroCostoId=l.LibroCostoId AND mc.MovimientoInventarioId=s.UltimoMovimientoId;

    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.GrupoInventario;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON inv.GrupoInventario AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.LibroCosto;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.LibroCosto AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.PoliticaValoracionGrupo;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.PoliticaValoracionGrupo AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.MovimientoCostoLibro;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.MovimientoCostoLibro AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD FILTER PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.SaldoCostoLibroBodega;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.SaldoCostoLibroBodega AFTER INSERT;');
    EXEC(N'ALTER SECURITY POLICY seg.EmpresaSecurityPolicy ADD BLOCK PREDICATE seg.fn_EmpresaAccess(EmpresaId) ON cost.SaldoCostoLibroBodega AFTER UPDATE;');
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('028_cost_books_and_history',N'Libros de costo configurables y consultas históricas deterministas');
    COMMIT;
    EXEC sys.sp_set_session_context @key=N'BypassRls',@value=NULL;
END;
GO

CREATE OR ALTER TRIGGER core.TR_Empresa_LibroCostoDefecto ON core.Empresa AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT cost.LibroCosto(EmpresaId,Codigo,Nombre,Categoria,FormulaValoracion,EsPrincipal,Estado)
    SELECT EmpresaId,'OPERATIVO',N'Costo operativo principal','OPERATIVO','PROMEDIO_MOVIL',1,'ACTIVO' FROM inserted i
    WHERE NOT EXISTS(SELECT 1 FROM cost.LibroCosto l WHERE l.EmpresaId=i.EmpresaId AND l.EsPrincipal=1);
END;
GO

CREATE OR ALTER TRIGGER inv.TR_MovimientoInventario_LibroPrincipal ON inv.MovimientoInventario AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    INSERT cost.MovimientoCostoLibro(EmpresaId,LibroCostoId,MovimientoInventarioId,CostoUnitarioAnterior,CostoUnitarioMovimiento,CostoUnitarioPosterior,ValorMovimiento,ValorTotalPosterior)
    SELECT i.EmpresaId,l.LibroCostoId,i.MovimientoInventarioId,i.CostoUnitarioAnterior,i.CostoUnitarioMovimiento,i.CostoPromedioPosterior,i.ValorMovimiento,i.ValorTotalPosterior
    FROM inserted i JOIN cost.LibroCosto l ON l.EmpresaId=i.EmpresaId AND l.EsPrincipal=1 AND l.Estado='ACTIVO';
    UPDATE s SET Existencia=i.ExistenciaPosterior,CostoUnitario=i.CostoPromedioPosterior,ValorTotal=i.ValorTotalPosterior,UltimoMovimientoCostoLibroId=mc.MovimientoCostoLibroId
    FROM cost.SaldoCostoLibroBodega s JOIN inserted i ON i.EmpresaId=s.EmpresaId AND i.BodegaId=s.BodegaId AND i.ArticuloId=s.ArticuloId
    JOIN cost.LibroCosto l ON l.EmpresaId=i.EmpresaId AND l.LibroCostoId=s.LibroCostoId AND l.EsPrincipal=1 AND l.Estado='ACTIVO'
    JOIN cost.MovimientoCostoLibro mc ON mc.EmpresaId=i.EmpresaId AND mc.LibroCostoId=l.LibroCostoId AND mc.MovimientoInventarioId=i.MovimientoInventarioId;
    INSERT cost.SaldoCostoLibroBodega(EmpresaId,LibroCostoId,BodegaId,ArticuloId,Existencia,CostoUnitario,ValorTotal,UltimoMovimientoCostoLibroId)
    SELECT i.EmpresaId,l.LibroCostoId,i.BodegaId,i.ArticuloId,i.ExistenciaPosterior,i.CostoPromedioPosterior,i.ValorTotalPosterior,mc.MovimientoCostoLibroId
    FROM inserted i JOIN cost.LibroCosto l ON l.EmpresaId=i.EmpresaId AND l.EsPrincipal=1 AND l.Estado='ACTIVO'
    JOIN cost.MovimientoCostoLibro mc ON mc.EmpresaId=i.EmpresaId AND mc.LibroCostoId=l.LibroCostoId AND mc.MovimientoInventarioId=i.MovimientoInventarioId
    WHERE NOT EXISTS(SELECT 1 FROM cost.SaldoCostoLibroBodega s WHERE s.EmpresaId=i.EmpresaId AND s.LibroCostoId=l.LibroCostoId AND s.BodegaId=i.BodegaId AND s.ArticuloId=i.ArticuloId);
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ConsultarInventarioAFecha @EmpresaId bigint,@FechaCorte date,@BodegaId bigint=NULL,@ArticuloId bigint=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.BodegaId,m.ArticuloId,a.Codigo,a.Descripcion,
           SUM(m.CantidadEntrada-m.CantidadSalida) Existencia,
           SUM(CASE WHEN m.CantidadSalida>0 THEN -m.ValorMovimiento ELSE m.ValorMovimiento END) ValorHistorico,
           CAST(CASE WHEN SUM(m.CantidadEntrada-m.CantidadSalida)=0 THEN 0 ELSE SUM(CASE WHEN m.CantidadSalida>0 THEN -m.ValorMovimiento ELSE m.ValorMovimiento END)/SUM(m.CantidadEntrada-m.CantidadSalida) END AS decimal(20,8)) CostoPromedioHistorico
    FROM inv.MovimientoInventario m JOIN inv.Articulo a ON a.EmpresaId=m.EmpresaId AND a.ArticuloId=m.ArticuloId
    WHERE m.EmpresaId=@EmpresaId AND m.FechaContable<=@FechaCorte AND (@BodegaId IS NULL OR m.BodegaId=@BodegaId) AND (@ArticuloId IS NULL OR m.ArticuloId=@ArticuloId)
    GROUP BY m.BodegaId,m.ArticuloId,a.Codigo,a.Descripcion ORDER BY m.BodegaId,a.Codigo;
END;
GO

CREATE OR ALTER PROCEDURE inv.usp_ConsultarEvolucionCosto @EmpresaId bigint,@ArticuloId bigint,@BodegaId bigint=NULL,@Desde date=NULL,@Hasta date=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MovimientoInventarioId,BodegaId,FechaMovimiento,FechaContable,TipoMovimiento,NumeroDocumento,CantidadEntrada,CantidadSalida,
           CostoUnitarioAnterior,CostoUnitarioMovimiento,CostoPromedioPosterior,ValorMovimiento,ValorTotalAnterior,ValorTotalPosterior,MovimientoRelacionadoId
    FROM inv.MovimientoInventario WHERE EmpresaId=@EmpresaId AND ArticuloId=@ArticuloId AND (@BodegaId IS NULL OR BodegaId=@BodegaId)
      AND (@Desde IS NULL OR FechaContable>=@Desde) AND (@Hasta IS NULL OR FechaContable<=@Hasta)
    ORDER BY MovimientoInventarioId;
END;
GO
