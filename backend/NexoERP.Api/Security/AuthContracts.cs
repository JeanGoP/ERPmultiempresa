namespace NexoERP.Api.Security;

public sealed record LoginRequest(string Correo,string Password);
public sealed record LoginResponse(string Token,DateTime ExpiraEnUtc,long UsuarioId,string NombreCompleto);
public sealed record AuthenticatedUser(long UsuarioId,string Correo,string NombreCompleto);
public sealed record PermissionResponse(string Codigo,string Modulo,string Accion,string Nombre,bool EsCritico);
public sealed record CompanyAccessResponse(long EmpresaId,string Codigo,string Nit,string RazonSocial,string MonedaFuncional);
