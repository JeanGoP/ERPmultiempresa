SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS(SELECT 1 FROM core.SchemaMigration WHERE MigrationId='016_api_authentication')
BEGIN
    BEGIN TRANSACTION;
    CREATE TABLE seg.UsuarioCredencial
    (
        UsuarioId bigint NOT NULL,
        PasswordHash varbinary(64) NOT NULL,
        PasswordSalt varbinary(32) NOT NULL,
        Iteraciones int NOT NULL CONSTRAINT DF_UsuarioCredencial_Iteraciones DEFAULT 210000,
        IntentosFallidos int NOT NULL CONSTRAINT DF_UsuarioCredencial_Intentos DEFAULT 0,
        BloqueadoHastaUtc datetime2(7) NULL,
        PasswordActualizadoEnUtc datetime2(7) NOT NULL CONSTRAINT DF_UsuarioCredencial_Fecha DEFAULT SYSUTCDATETIME(),
        RowVersion rowversion NOT NULL,
        CONSTRAINT PK_UsuarioCredencial PRIMARY KEY CLUSTERED(UsuarioId),
        CONSTRAINT FK_UsuarioCredencial_Usuario FOREIGN KEY(UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_UsuarioCredencial_Iteraciones CHECK(Iteraciones>=100000),
        CONSTRAINT CK_UsuarioCredencial_Intentos CHECK(IntentosFallidos>=0)
    );
    CREATE TABLE seg.SesionApi
    (
        SesionApiId uniqueidentifier NOT NULL CONSTRAINT DF_SesionApi_Id DEFAULT NEWSEQUENTIALID(),
        UsuarioId bigint NOT NULL,
        TokenHash binary(32) NOT NULL,
        CreadaEnUtc datetime2(7) NOT NULL CONSTRAINT DF_SesionApi_Creada DEFAULT SYSUTCDATETIME(),
        ExpiraEnUtc datetime2(7) NOT NULL,
        RevocadaEnUtc datetime2(7) NULL,
        UltimoUsoEnUtc datetime2(7) NULL,
        DireccionIp nvarchar(64) NULL,
        CONSTRAINT PK_SesionApi PRIMARY KEY CLUSTERED(SesionApiId),
        CONSTRAINT UQ_SesionApi_TokenHash UNIQUE(TokenHash),
        CONSTRAINT FK_SesionApi_Usuario FOREIGN KEY(UsuarioId) REFERENCES seg.Usuario(UsuarioId),
        CONSTRAINT CK_SesionApi_Expiracion CHECK(ExpiraEnUtc>CreadaEnUtc)
    );
    CREATE INDEX IX_SesionApi_UsuarioActiva ON seg.SesionApi(UsuarioId,ExpiraEnUtc) INCLUDE(RevocadaEnUtc,UltimoUsoEnUtc);
    INSERT core.SchemaMigration(MigrationId,Descripcion) VALUES('016_api_authentication',N'Credenciales PBKDF2, sesiones opacas y autorización por empresa para la API');
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE seg.usp_RevocarSesionApi @UsuarioId bigint,@TokenHash binary(32)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE seg.SesionApi SET RevocadaEnUtc=COALESCE(RevocadaEnUtc,SYSUTCDATETIME()) WHERE UsuarioId=@UsuarioId AND TokenHash=@TokenHash;
END;
GO
