namespace NexoERP.Api.Security;

public sealed record LoginRequest(string Correo,string Password);
public sealed record LoginResponse(string Token,DateTime ExpiraEnUtc,long UsuarioId,string NombreCompleto,bool EsSuperAdministrador);
public sealed record AuthenticatedUser(long UsuarioId,string Correo,string NombreCompleto,bool EsSuperAdministrador);
public sealed record PermissionResponse(string Codigo,string Modulo,string Accion,string Nombre,bool EsCritico);
public sealed record CompanyAccessResponse(long EmpresaId,string Codigo,string Nit,string RazonSocial,string MonedaFuncional);
public sealed record CreateCompanyRequest(string Codigo,string Nit,string? DigitoVerificacion,string RazonSocial,string MonedaFuncional,string? ZonaHoraria,string? MarcoContable);
public sealed record OperationalSetupResponse(long UnidadMedidaId,long BodegaId,long PeriodoInventarioId,long PeriodoContableId,string PeriodoCodigo);
public sealed record SecurityRoleSummary(long RolId,string Codigo,string Nombre);
public sealed record SecurityUserResponse(long UsuarioId,string Correo,string NombreCompleto,bool ActivoGlobal,bool AccesoActivo,IReadOnlyList<SecurityRoleSummary> Roles);
public sealed record CreateSecurityUserRequest(string Correo,string NombreCompleto,string Password,bool AccesoActivo,IReadOnlyList<long> RolIds);
public sealed record UpdateSecurityUserRequest(bool AccesoActivo,IReadOnlyList<long> RolIds);
public sealed record ResetSecurityPasswordRequest(string Password);
public sealed record SecurityPermissionResponse(long PermisoId,string Codigo,string Modulo,string Accion,string Nombre,bool EsCritico);
public sealed record SecurityRoleResponse(long RolId,string Codigo,string Nombre,IReadOnlyList<long> PermisoIds);
public sealed record SaveSecurityRoleRequest(string Codigo,string Nombre,IReadOnlyList<long> PermisoIds);
