namespace NexoERP.Api.Security;

public static class PermissionEndpointFilterExtensions
{
    public static RouteHandlerBuilder RequireSuperAdministrator(this RouteHandlerBuilder builder)
        => builder.AddEndpointFilter(async (context,next) =>
        {
            var http=context.HttpContext;
            if(!http.Items.TryGetValue("EsSuperAdministrador",out var value)||value is not true)
                return Results.Json(new { error="Esta operación requiere un superadministrador global." },statusCode:StatusCodes.Status403Forbidden);
            return await next(context);
        });

    public static RouteHandlerBuilder RequireErpPermission(this RouteHandlerBuilder builder,string permission)
        => builder.AddEndpointFilter(async (context,next) =>
        {
            var http=context.HttpContext;
            if(!http.Request.RouteValues.TryGetValue("empresaId",out var rawCompany)
               || !long.TryParse(Convert.ToString(rawCompany),out var companyId)
               || !http.Items.TryGetValue("UsuarioId",out var rawUser))
                return Results.Forbid();
            var auth=http.RequestServices.GetRequiredService<AuthRepository>();
            if(!await auth.HasPermissionAsync(Convert.ToInt64(rawUser),companyId,permission,http.RequestAborted))
                return Results.Json(new { error="El usuario no tiene el permiso requerido para esta operacion.",permission },statusCode:StatusCodes.Status403Forbidden);
            return await next(context);
        });
}
