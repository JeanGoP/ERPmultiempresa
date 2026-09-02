namespace NexoERP.Api.MasterData;

public sealed record SupplierResponse(
    long TerceroId,string TipoIdentificacion,string NumeroIdentificacion,string? DigitoVerificacion,string RazonSocial,
    string? NombreComercial,string? CodigoResponsabilidadFiscal,string? RegimenFiscalCodigo,string? RegimenFiscalNombre,
    string? Direccion,string? CiudadCodigo,string? Ciudad,string? DepartamentoCodigo,string? Departamento,string? CodigoPostal,
    string? PaisCodigo,string? Pais,string? ContactoNombre,string? Telefono,string? Correo,string? SitioWeb,string? DatosXmlJson,bool Activo);
public sealed record UnitOfMeasureResponse(long UnidadMedidaId,string Codigo,string Nombre,string Simbolo,bool Activa);
public sealed record ArticleResponse(long ArticuloId,string Codigo,string Descripcion,string Tipo,bool ManejaInventario,long UnidadBaseId,string UnidadBase,bool ManejaLote,bool ManejaSerial,bool RequiereVencimiento,decimal? PesoBaseKg,decimal? VolumenBaseM3,bool Activo);
public sealed record ItemMappingResponse(long HomologacionArticuloProveedorId,long TerceroId,string ProveedorIdentificacion,string Proveedor,string CodigoExterno,string? DescripcionExterna,long ArticuloId,string ArticuloCodigo,string Articulo,string? UnidadCodigo,decimal FactorAUnidadBase,bool Activa);
public sealed record MasterSaveResponse(long Id,bool Creado);

public sealed record SaveSupplierRequest(
    string TipoIdentificacion,string NumeroIdentificacion,string? DigitoVerificacion,string RazonSocial,
    string? NombreComercial,string? CodigoResponsabilidadFiscal,string? RegimenFiscalCodigo,string? RegimenFiscalNombre,
    string? Direccion,string? CiudadCodigo,string? Ciudad,string? DepartamentoCodigo,string? Departamento,string? CodigoPostal,
    string? PaisCodigo,string? Pais,string? ContactoNombre,string? Telefono,string? Correo,string? SitioWeb,string? DatosXmlJson,long? UsuarioId);
public sealed record SaveUnitRequest(string Codigo,string Nombre,string Simbolo,long? UsuarioId);
public sealed record SaveArticleRequest(string Codigo,string Descripcion,string Tipo,long UnidadBaseId,bool ManejaInventario,bool ManejaLote,bool ManejaSerial,bool RequiereVencimiento,decimal? PesoBaseKg,decimal? VolumenBaseM3,long? UsuarioId);
public sealed record SaveArticleUnitRequest(long UnidadMedidaId,decimal FactorAUnidadBase,bool EsUnidadCompra,bool EsUnidadVenta,long? UsuarioId);
public sealed record SaveWarehouseRequest(string Codigo,string Nombre,bool UsaUbicaciones,bool EsTransito,long? UsuarioId);
public sealed record SaveItemMappingRequest(long TerceroId,string CodigoExterno,string? DescripcionExterna,long ArticuloId,long? UnidadMedidaId,decimal FactorAUnidadBase,long? UsuarioId);
