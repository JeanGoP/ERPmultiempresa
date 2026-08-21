param(
    [string]$Instance='(localdb)\MSSQLLocalDB',
    [int]$Port=5199
)

$ErrorActionPreference='Stop'
$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$databaseName="NexoErpApiQa_$PID"
$safeDatabaseName=$databaseName.Replace(']',']]')
$baseUrl="http://127.0.0.1:$Port"
$apiProcess=$null
$oldConnection=$env:ConnectionStrings__NexoErp
$outputLog=Join-Path $env:TEMP "nexo-api-$PID.out.log"
$errorLog=Join-Path $env:TEMP "nexo-api-$PID.err.log"
$adminPassword='ApiQa-Admin-2026!'
$viewerPassword='ApiQa-Viewer-2026!'
$superPassword='ApiQa-Super-2026!'

function Assert-Status([scriptblock]$Request,[int]$Expected,[string]$Message) {
    try {
        $response=& $Request
        $status=[int]$response.StatusCode
    } catch {
        if($_.Exception.Response){ $status=[int]$_.Exception.Response.StatusCode.value__ } else { throw }
    }
    if($status -ne $Expected){ throw "$Message Se esperaba HTTP $Expected y se obtuvo $status." }
}

function New-TestSecureString([string]$Value) {
    $secure=[Security.SecureString]::new()
    foreach($character in $Value.ToCharArray()){ $secure.AppendChar($character) }
    $secure.MakeReadOnly()
    return $secure
}

try {
    & (Join-Path $projectRoot 'database\scripts\init-localdb.ps1') -DatabaseName $databaseName -Instance $Instance
    $setupSql=@"
SET XACT_ABORT ON;
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
BEGIN TRANSACTION;
INSERT core.Empresa(Codigo,Nit,RazonSocial) VALUES('APIQA','900777001',N'Empresa QA API');
DECLARE @EmpresaId bigint=SCOPE_IDENTITY();
INSERT core.EmpresaConfiguracion(EmpresaId) VALUES(@EmpresaId);
UPDATE core.EmpresaConfiguracion SET PermiteInventarioNegativo=1 WHERE EmpresaId=@EmpresaId;
INSERT inv.UnidadMedida(EmpresaId,Codigo,Nombre,Simbolo) VALUES(@EmpresaId,'UND',N'Unidad','und');
DECLARE @UnidadId bigint=SCOPE_IDENTITY();
INSERT inv.Articulo(EmpresaId,Codigo,Descripcion,Tipo,ManejaInventario,UnidadBaseId) VALUES(@EmpresaId,'ART-API',N'Articulo API','INVENTARIO',1,@UnidadId);
INSERT inv.Bodega(EmpresaId,Codigo,Nombre) VALUES(@EmpresaId,'BOD-API',N'Bodega API');
INSERT core.PeriodoInventario(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31');
INSERT core.PeriodoContable(EmpresaId,Codigo,FechaInicio,FechaFin) VALUES(@EmpresaId,'2026-08','2026-08-01','2026-08-31');
INSERT cont.CuentaContable(EmpresaId,Codigo,Nombre,Tipo,Naturaleza) VALUES
(@EmpresaId,'513595',N'Servicios generales','GASTO','D'),
(@EmpresaId,'240810',N'IVA descontable','ACTIVO','D'),
(@EmpresaId,'236525',N'Retencion de servicios','PASIVO','C'),
(@EmpresaId,'220505',N'Proveedores nacionales','PASIVO','C');
INSERT cost.ConceptoCostoAdquisicion(EmpresaId,Codigo,Nombre,Tratamiento,MetodoDistribucionDefecto) VALUES(@EmpresaId,'FLETE',N'Flete nacional','CAPITALIZABLE','VALOR_COMPRA');
COMMIT;
"@
    & sqlcmd -S $Instance -E -b -d $databaseName -Q $setupSql
    if($LASTEXITCODE -ne 0){ throw 'No fue posible preparar la empresa para la prueba API.' }

    $adminSecure=New-TestSecureString $adminPassword
    $viewerSecure=New-TestSecureString $viewerPassword
    $superSecure=New-TestSecureString $superPassword
    & (Join-Path $projectRoot 'database\scripts\set-local-user.ps1') -Correo 'admin.api@qa.local' -Password $adminSecure -NombreCompleto 'Administrador API QA' -EmpresaCodigo 'APIQA' -DatabaseName $databaseName -Instance $Instance
    & (Join-Path $projectRoot 'database\scripts\set-local-user.ps1') -Correo 'consulta.api@qa.local' -Password $viewerSecure -NombreCompleto 'Consulta API QA' -EmpresaCodigo 'APIQA' -DatabaseName $databaseName -Instance $Instance
    & (Join-Path $projectRoot 'database\scripts\set-local-user.ps1') -Correo 'super.api@qa.local' -Password $superSecure -NombreCompleto 'Superadministrador API QA' -EmpresaCodigo 'APIQA' -DatabaseName $databaseName -Instance $Instance
    $viewerSql=@"
DECLARE @EmpresaId bigint=(SELECT EmpresaId FROM core.Empresa WHERE Codigo='APIQA');
DECLARE @UsuarioId bigint=(SELECT UsuarioId FROM seg.Usuario WHERE Correo='consulta.api@qa.local');
DECLARE @AdminId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='ADMIN');
DECLARE @ViewerId bigint=(SELECT RolId FROM seg.Rol WHERE Codigo='API_VIEWER');
IF @ViewerId IS NULL BEGIN INSERT seg.Rol(Codigo,Nombre) VALUES('API_VIEWER',N'Consulta API'); SET @ViewerId=SCOPE_IDENTITY(); END;
IF NOT EXISTS(SELECT 1 FROM seg.UsuarioEmpresaRol WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND RolId=@ViewerId)
    INSERT seg.UsuarioEmpresaRol(EmpresaId,UsuarioId,RolId) VALUES(@EmpresaId,@UsuarioId,@ViewerId);
UPDATE seg.UsuarioEmpresaRol SET Activo=0 WHERE EmpresaId=@EmpresaId AND UsuarioId=@UsuarioId AND RolId=@AdminId;
UPDATE seg.Usuario SET EsSuperAdministrador=1 WHERE Correo='super.api@qa.local';
DELETE FROM seg.UsuarioEmpresaRol WHERE UsuarioId=(SELECT UsuarioId FROM seg.Usuario WHERE Correo='super.api@qa.local');
"@
    & sqlcmd -S $Instance -E -b -d $databaseName -Q $viewerSql
    if($LASTEXITCODE -ne 0){ throw 'No fue posible preparar el usuario restringido.' }
    $companyId=[long]((& sqlcmd -S $Instance -E -h -1 -W -d $databaseName -Q "SET NOCOUNT ON; SELECT EmpresaId FROM core.Empresa WHERE Codigo='APIQA';") | Select-Object -First 1).Trim()

    $env:ConnectionStrings__NexoErp="Server=$Instance;Database=$databaseName;Integrated Security=true;TrustServerCertificate=true"
    $apiProcess=Start-Process -FilePath 'dotnet' -ArgumentList @('run','--no-build','--configuration','Release','--project','backend/NexoERP.Api','--urls',$baseUrl) -WorkingDirectory $projectRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $outputLog -RedirectStandardError $errorLog
    $healthy=$false
    for($attempt=0;$attempt -lt 30;$attempt++){
        Start-Sleep -Milliseconds 300
        try { $health=Invoke-RestMethod -Uri "$baseUrl/api/v1/health" -Method Get; $healthy=$true; break } catch { if($apiProcess.HasExited){ break } }
    }
    if(-not $healthy){ throw "La API no inicio. $(Get-Content $errorLog -Raw -ErrorAction SilentlyContinue)" }
    if($health.status -ne 'ok' -or $health.migrations -ne 39){ throw 'La salud de la API no reporto las 39 migraciones esperadas.' }
    $ready=Invoke-RestMethod -Uri "$baseUrl/api/v1/health/ready" -Method Get
    if($ready.status -ne 'ready' -or $ready.discardedOutbox -ne 0){ throw 'La comprobacion de disponibilidad operativa no quedo lista.' }

    $superLogin=Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body (@{correo='super.api@qa.local';password=$superPassword}|ConvertTo-Json)
    if(-not $superLogin.esSuperAdministrador){ throw 'La API no identifico el superadministrador global.' }
    $superHeaders=@{Authorization="Bearer $($superLogin.token)"}
    $superCompany=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies" -Headers $superHeaders -Method Post -ContentType 'application/json' -Body (@{codigo='SUPERQA';nit='900777099';digitoVerificacion='1';razonSocial='Empresa creada por superadministrador';monedaFuncional='COP';zonaHoraria='America/Bogota';marcoContable='GRUPO_2'}|ConvertTo-Json)
    $superWarehouses=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$($superCompany.empresaId)/warehouses" -Headers $superHeaders -Method Get
    $superPeriods=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$($superCompany.empresaId)/inventory-periods" -Headers $superHeaders -Method Get
    $superAudit=[int]((& sqlcmd -S $Instance -E -h -1 -W -d $databaseName -Q "SET NOCOUNT ON; EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1; SELECT COUNT(*) FROM audit.Evento WHERE EmpresaId=$($superCompany.empresaId) AND Operacion='EMPRESA_CREADA' AND ISJSON(ValoresPosteriores)=1;") | Select-Object -First 1).Trim()
    $superAssignments=[int]((& sqlcmd -S $Instance -E -h -1 -W -d $databaseName -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM seg.UsuarioEmpresaRol WHERE UsuarioId=(SELECT UsuarioId FROM seg.Usuario WHERE Correo='super.api@qa.local');") | Select-Object -First 1).Trim()
    if($superCompany.codigo -ne 'SUPERQA' -or $superAudit -ne 1 -or $superAssignments -ne 0 -or @($superWarehouses).Count -ne 1 -or @($superPeriods).Count -ne 1){ throw "La creación global no dejó empresa, bodega, periodo o auditoría preparados correctamente. codigo=$($superCompany.codigo), auditoria=$superAudit, asignaciones=$superAssignments" }
    $preparedCompany=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/setup/operational-defaults" -Headers $superHeaders -Method Post -ContentType 'application/json' -Body '{}'
    if($preparedCompany.bodegaId -le 0 -or $preparedCompany.periodoInventarioId -le 0 -or $preparedCompany.unidadMedidaId -le 0){ throw 'La preparación idempotente de una empresa existente no devolvió sus maestros iniciales.' }

    Assert-Status { Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/inventory/balances" -Method Get } 401 'Una consulta anonima no fue rechazada.'

    $adminLogin=Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body (@{correo='admin.api@qa.local';password=$adminPassword}|ConvertTo-Json)
    $adminHeaders=@{Authorization="Bearer $($adminLogin.token)"}
    $companies=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies" -Headers $adminHeaders -Method Get
    if(@($companies).Count -ne 1 -or @($companies)[0].empresaId -ne $companyId){ throw 'La API no devolvio la empresa autorizada.' }
    $permissions=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/permissions" -Headers $adminHeaders -Method Get
    if(@($permissions).Count -lt 23 -or 'INVENTARIO.AJUSTE.REVERSAR' -notin $permissions.codigo -or 'COMPRAS.HOMOLOGACION.ADMINISTRAR' -notin $permissions.codigo){ throw 'El administrador no recibio sus permisos granulares.' }
    $securityPermissions=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/permissions" -Headers $adminHeaders -Method Get
    $securityRoles=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/roles" -Headers $adminHeaders -Method Get
    $purchaseCreatePermission=[long](@($securityPermissions)|Where-Object codigo -eq 'COMPRAS.DOCUMENTO.CREAR'|Select-Object -First 1).permisoId
    $receiptPermission=[long](@($securityPermissions)|Where-Object codigo -eq 'COMPRAS.RECEPCION.CONTABILIZAR'|Select-Object -First 1).permisoId
    if($purchaseCreatePermission -le 0 -or @($securityRoles).Count -lt 1){ throw 'La API de seguridad no publico roles y permisos.' }
    $operatorRole=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/roles" -Headers $superHeaders -Method Post -ContentType 'application/json' -Body (@{codigo='OPERADOR_QA';nombre='Operador de compras QA';permisoIds=@($purchaseCreatePermission)}|ConvertTo-Json)
    $securityPassword='ApiQa-Operador-2026!'
    $createdSecurityUser=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/users" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{correo='operador.api@qa.local';nombreCompleto='Operador API QA';password=$securityPassword;accesoActivo=$true;rolIds=@([long]$operatorRole.rolId)}|ConvertTo-Json)
    if($createdSecurityUser.usuarioExistente -or $createdSecurityUser.user.roles[0].codigo -ne 'OPERADOR_QA'){ throw 'La creación del usuario no asignó el rol solicitado.' }
    $operatorLogin=Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body (@{correo='operador.api@qa.local';password=$securityPassword}|ConvertTo-Json)
    $operatorHeaders=@{Authorization="Bearer $($operatorLogin.token)"}
    $operatorPermissions=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/permissions" -Headers $operatorHeaders -Method Get
    if(@($operatorPermissions).Count -ne 1 -or @($operatorPermissions)[0].codigo -ne 'COMPRAS.DOCUMENTO.CREAR'){ throw 'El rol personalizado no limitó los permisos del usuario.' }
    $operatorRole=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/roles/$($operatorRole.rolId)" -Headers $superHeaders -Method Put -ContentType 'application/json' -Body (@{codigo='OPERADOR_QA';nombre='Operador de compras QA';permisoIds=@($purchaseCreatePermission,$receiptPermission)}|ConvertTo-Json)
    $operatorPermissions=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/permissions" -Headers $operatorHeaders -Method Get
    if('COMPRAS.RECEPCION.CONTABILIZAR' -notin $operatorPermissions.codigo){ throw 'La edición del rol no actualizó los permisos efectivos.' }
    $newSecurityPassword='ApiQa-Operador-Nueva-2026!'
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/security/users/$($createdSecurityUser.user.usuarioId)/password" -Headers $adminHeaders -Method Put -ContentType 'application/json' -Body (@{password=$newSecurityPassword}|ConvertTo-Json)|Out-Null
    Assert-Status { Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/permissions" -Headers $operatorHeaders -Method Get } 401 'El cambio de contraseña no revocó las sesiones anteriores.'
    $operatorLogin=Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body (@{correo='operador.api@qa.local';password=$newSecurityPassword}|ConvertTo-Json)
    $operatorHeaders=@{Authorization="Bearer $($operatorLogin.token)"}
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/users/$($createdSecurityUser.user.usuarioId)" -Headers $adminHeaders -Method Put -ContentType 'application/json' -Body (@{accesoActivo=$false;rolIds=@([long]$operatorRole.rolId)}|ConvertTo-Json)
    $securityUsers=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/users" -Headers $adminHeaders -Method Get
    $disabledUser=@($securityUsers)|Where-Object usuarioId -eq $createdSecurityUser.user.usuarioId|Select-Object -First 1
    if($disabledUser.accesoActivo -or $disabledUser.roles[0].rolId -ne $operatorRole.rolId){ throw 'La desactivación no conservó la asignación de rol.' }
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/security/users/$($createdSecurityUser.user.usuarioId)" -Headers $adminHeaders -Method Put -ContentType 'application/json' -Body (@{accesoActivo=$true;rolIds=@([long]$operatorRole.rolId)}|ConvertTo-Json)
    $operations=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/operations/status" -Headers $adminHeaders -Method Get
    if($null -eq $operations.company -or $null -eq $operations.runtime){ throw 'La API no publico el estado operativo y las metricas.' }
    $units=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/units" -Headers $adminHeaders -Method Get
    $unitId=[long](@($units)[0].unidadMedidaId)
    $supplierSaved=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/suppliers" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{tipoIdentificacion='NIT';numeroIdentificacion='890301886';digitoVerificacion='5';razonSocial='Proveedor API QA'}|ConvertTo-Json)
    $articleSaved=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/articles" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{codigo='MOTO-API';descripcion='Motocicleta API';tipo='INVENTARIO';unidadBaseId=$unitId;manejaInventario=$true;manejaLote=$true;manejaSerial=$true;requiereVencimiento=$true;pesoBaseKg=$null;volumenBaseM3=$null}|ConvertTo-Json)
    $serviceSaved=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/articles" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{codigo='SERV-API';descripcion='Mantenimiento proveedor';tipo='SERVICIO';unidadBaseId=$unitId;manejaInventario=$false;manejaLote=$false;manejaSerial=$false;requiereVencimiento=$false;pesoBaseKg=$null;volumenBaseM3=$null}|ConvertTo-Json)
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/articles/$($articleSaved.id)/units" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{unidadMedidaId=$unitId;factorAUnidadBase=1;esUnidadCompra=$true;esUnidadVenta=$true}|ConvertTo-Json)
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/warehouses" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{codigo='BOD-API-2';nombre='Bodega API dos';usaUbicaciones=$true;esTransito=$false}|ConvertTo-Json)
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/item-mappings" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{terceroId=$supplierSaved.id;codigoExterno='357683';descripcionExterna='Moto proveedor';articuloId=$articleSaved.id;unidadMedidaId=$unitId;factorAUnidadBase=1}|ConvertTo-Json)
    $mappings=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/item-mappings?terceroId=$($supplierSaved.id)" -Headers $adminHeaders -Method Get
    if(@($mappings).Count -ne 1 -or @($mappings)[0].codigoExterno -ne '357683'){ throw 'La API no guardo o consulto la homologacion.' }
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/history?fecha=2026-08-31" -Headers $adminHeaders -Method Get
    $serials=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/serialized-units" -Headers $adminHeaders -Method Get
    $serialCount=if($null -eq $serials){0}else{@($serials).Count}
    if($serialCount -ne 0){ throw 'La empresa temporal contiene seriales inesperados.' }

    $warehouses=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/warehouses" -Headers $adminHeaders -Method Get
    $periods=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory-periods" -Headers $adminHeaders -Method Get
    $warehouseId=[long](@($warehouses)|Where-Object codigo -eq 'BOD-API'|Select-Object -First 1).bodegaId
    $periodId=[long](@($periods)[0].periodoInventarioId)
    $autoBody=@{
        proveedorIdentificacion='890301886';proveedorRazonSocial='Proveedor API QA';tipoDocumento='FACTURA';numeroDocumento='FV-AUTO-ITEM-1';fechaDocumento='2026-08-20';fechaVencimiento='2026-08-20';condicionPago='CONTADO';diasCredito=0;crearArticulosFaltantes=$true;moneda='COP';
        cufeCude='CUFE-AUTO-ITEM-1';fuente='XML_DIAN';subtotalBruto=100;descuentoTotal=0;impuestoTotal=19;cargoTotal=0;totalPagar=119;xmlOriginal='<Invoice><ID>FV-AUTO-ITEM-1</ID></Invoice>';
        lineas=@(@{numeroLinea=1;articuloId=$null;codigoExterno='MOTO-AUTO-EXT';descripcion='Motocicleta creada desde XML';clasificacion='INVENTARIO';cantidad=1;unidadMedidaId=$null;unidadCodigo='94';manejaSerial=$true;factorAUnidadBase=1;precioUnitario=100;subtotalBruto=100;descuento=0;impuesto=19;retencion=0;cargo=0;totalNeto=100;numeroLote=$null;fechaVencimiento=$null;
            seriales=@(@{numeroUnidad=1;serial=$null;motor='MOT-AUTO-001';chasis='CHA-AUTO-001';vin='VIN-AUTO-001';color='NEGRO';modelo='2027';informacionOriginal='MOT-AUTO-001;CHA-AUTO-001'})})
    }
    $autoCreated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($autoBody|ConvertTo-Json -Depth 8)
    $autoSecond=@{}+$autoBody;$autoSecond.numeroDocumento='FV-AUTO-ITEM-2';$autoSecond.cufeCude='CUFE-AUTO-ITEM-2';$autoSecond.xmlOriginal='<Invoice><ID>FV-AUTO-ITEM-2</ID></Invoice>';$autoSecond.documentoGuid=[guid]::NewGuid()
    $autoReused=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($autoSecond|ConvertTo-Json -Depth 8)
    $articlesAfterAuto=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/articles" -Headers $adminHeaders -Method Get
    if($autoCreated.articulosCreados -ne 1 -or $autoReused.articulosCreados -ne 0 -or -not (@($articlesAfterAuto)|Where-Object codigo -eq 'MOTO-AUTO-EXT')){ throw 'La API no creó el artículo con el código del proveedor o no lo reutilizó correctamente.' }
    $documentBody=@{
        proveedorIdentificacion='890301886';proveedorRazonSocial='Proveedor API QA';tipoDocumento='FACTURA';numeroDocumento='FV-POINT4';fechaDocumento='2026-08-20';fechaVencimiento='2026-09-19';condicionPago='CREDITO';diasCredito=30;crearArticulosFaltantes=$false;moneda='COP';
        cufeCude='CUFE-POINT4-UNICO';fuente='XML_DIAN';subtotalBruto=100;descuentoTotal=10;impuestoTotal=17.1;cargoTotal=0;totalPagar=107.1;xmlOriginal='<Invoice><ID>FV-POINT4</ID></Invoice>';
        lineas=@(@{numeroLinea=1;articuloId=[long]$articleSaved.id;codigoExterno='357683';descripcion='Motocicleta prueba punto 4';clasificacion='INVENTARIO';cantidad=1;unidadMedidaId=$unitId;factorAUnidadBase=1;precioUnitario=100;subtotalBruto=100;descuento=10;impuesto=17.1;cargo=0;totalNeto=90;numeroLote=$null;fechaVencimiento=$null;
            seriales=@(@{numeroUnidad=1;serial='SER-P4-001';motor='MOT-P4-001';chasis='CHA-P4-001';vin='VIN-P4-001';color='NEGRO';modelo='2026';informacionOriginal='NEGRO;CHA-P4-001;MOT-P4-001;;2026'})})
    }
    $created=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($documentBody|ConvertTo-Json -Depth 8)
    $repeated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($documentBody|ConvertTo-Json -Depth 8)
    if($repeated.documentoProveedorId -ne $created.documentoProveedorId -or -not $repeated.yaExistia){ throw 'La repeticion del XML no fue idempotente.' }
    $sameNumber=@{}+$documentBody; $sameNumber.cufeCude='CUFE-POINT4-DIFERENTE'; $sameNumber.xmlOriginal='<Invoice><ID>FV-POINT4</ID><Note>otra copia</Note></Invoice>'
    $repeatedNumber=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($sameNumber|ConvertTo-Json -Depth 8)
    if($repeatedNumber.documentoProveedorId -ne $created.documentoProveedorId -or -not $repeatedNumber.yaExistia){ throw 'El control proveedor, tipo y numero no fue idempotente.' }
    $draft=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($created.documentoProveedorId)" -Headers $adminHeaders -Method Get
    if(-not $draft.xmlOriginalGuardado -or $draft.descuentoTotal -ne 10 -or $draft.unidadesSerializadas -ne 1 -or $draft.estado -ne 'BORRADOR'){ throw 'El borrador no conservo XML, descuento, seriales o estado.' }
    $savedDocuments=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents?q=MOT-P4-001" -Headers $adminHeaders -Method Get
    $savedDetail=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($created.documentoProveedorId)/detail" -Headers $adminHeaders -Method Get
    if(@($savedDocuments).Count -ne 1 -or @($savedDetail.lineas).Count -ne 1 -or @($savedDetail.lineas[0].seriales).Count -ne 1 -or $savedDetail.lineas[0].seriales[0].motor -ne 'MOT-P4-001' -or $savedDetail.lineas[0].seriales[0].chasis -ne 'CHA-P4-001' -or $savedDetail.lineas[0].seriales[0].color -ne 'NEGRO' -or $savedDetail.lineas[0].seriales[0].modelo -ne '2026'){ throw 'La bandeja de entradas no recuperó el borrador con todos sus seriales.' }
    $rejected=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($autoReused.documentoProveedorId)/reject" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body '{}'
    $rejectedAgain=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($autoReused.documentoProveedorId)/reject" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body '{}'
    if($rejected.estado -ne 'RECHAZADO' -or -not $rejectedAgain.yaExistia){ throw 'La anulación segura del borrador no fue idempotente.' }
    $prepared=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($created.documentoProveedorId)/prepare" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=$warehouseId;periodoInventarioId=$periodId;fechaContable='2026-08-20';numeroRecepcion='ENT-FV-POINT4';numeroCausacion=$null}|ConvertTo-Json)
    $preparedAgain=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($created.documentoProveedorId)/prepare" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=$warehouseId;periodoInventarioId=$periodId;fechaContable='2026-08-20';numeroRecepcion='ENT-FV-POINT4';numeroCausacion=$null}|ConvertTo-Json)
    if($prepared.recepcionMercanciaId -ne $preparedAgain.recepcionMercanciaId){ throw 'La preparacion duplico la recepcion.' }
    $beforeMovements=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($prepared.recepcionMercanciaId)/movements" -Headers $adminHeaders -Method Get
    if($null -ne $beforeMovements -and @($beforeMovements).Count -ne 0){ throw 'Preparar la recepcion afecto Kardex antes de la confirmacion.' }
    $posted=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($prepared.recepcionMercanciaId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    $postedAgain=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($prepared.recepcionMercanciaId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    if($posted.movimientos -ne 1 -or -not $postedAgain.yaExistia){ throw 'La contabilizacion de la recepcion no fue idempotente.' }
    $movements=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($prepared.recepcionMercanciaId)/movements" -Headers $adminHeaders -Method Get
    if(@($movements).Count -ne 1 -or @($movements)[0].cantidadEntrada -ne 1){ throw 'El resultado de Kardex no corresponde con la factura.' }
    $serials=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/serialized-units" -Headers $adminHeaders -Method Get
    if(@($serials).Count -ne 1 -or @($serials)[0].motor -ne 'MOT-P4-001' -or @($serials)[0].chasis -ne 'CHA-P4-001'){ throw 'Motor y chasis no llegaron a la unidad serializada.' }

    $manualGuid=[guid]::NewGuid()
    $manualBody=@{
        proveedorIdentificacion='890301886';proveedorRazonSocial='Proveedor API QA';tipoDocumento='FACTURA';numeroDocumento='FV-MANUAL-P5';fechaDocumento='2026-08-20';fechaVencimiento='2026-09-19';condicionPago='CREDITO';diasCredito=30;crearArticulosFaltantes=$false;moneda='COP';
        cufeCude=$null;fuente='MANUAL';subtotalBruto=100;descuentoTotal=15;impuestoTotal=17.1;cargoTotal=5;totalPagar=107.1;xmlOriginal=$null;documentoGuid=$manualGuid;
        lineas=@(@{numeroLinea=1;articuloId=[long]$articleSaved.id;codigoExterno='MOTO-MANUAL';descripcion='Motocicleta captura manual';clasificacion='INVENTARIO';cantidad=1;unidadMedidaId=$unitId;factorAUnidadBase=1;precioUnitario=100;subtotalBruto=100;descuento=15;impuesto=17.1;cargo=5;totalNeto=90;numeroLote='LOTE-P5-001';fechaVencimiento='2027-08-20';
            seriales=@(@{numeroUnidad=1;serial='SER-P5-001';motor='MOT-P5-001';chasis='CHA-P5-001';vin='VIN-P5-001';color='ROJO';modelo='2027';informacionOriginal='SER-P5-001;MOT-P5-001;CHA-P5-001;VIN-P5-001;ROJO;2027'})})
    }
    $manualCreated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($manualBody|ConvertTo-Json -Depth 8)
    $manualRepeated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($manualBody|ConvertTo-Json -Depth 8)
    if($manualCreated.documentoProveedorId -ne $manualRepeated.documentoProveedorId -or -not $manualRepeated.yaExistia){ throw 'El borrador manual no fue idempotente.' }
    $manualDraft=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($manualCreated.documentoProveedorId)" -Headers $adminHeaders -Method Get
    if($manualDraft.xmlOriginalGuardado -or $manualDraft.descuentoTotal -ne 15 -or $manualDraft.cargoTotal -ne 5 -or $manualDraft.unidadesSerializadas -ne 1){ throw 'El borrador manual no conservo descuentos, cargos o seriales.' }
    $manualPrepared=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($manualCreated.documentoProveedorId)/prepare" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=$warehouseId;periodoInventarioId=$periodId;fechaContable='2026-08-20';numeroRecepcion='ENT-FV-MANUAL-P5';numeroCausacion=$null}|ConvertTo-Json)
    $manualBefore=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($manualPrepared.recepcionMercanciaId)/movements" -Headers $adminHeaders -Method Get
    if($null -ne $manualBefore -and @($manualBefore).Count -ne 0){ throw 'Preparar la entrada manual afecto Kardex antes de confirmar.' }
    $manualPosted=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($manualPrepared.recepcionMercanciaId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    $manualPostedAgain=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($manualPrepared.recepcionMercanciaId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    if($manualPosted.movimientos -ne 1 -or -not $manualPostedAgain.yaExistia){ throw 'La entrada manual no fue idempotente.' }
    $manualMovements=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($manualPrepared.recepcionMercanciaId)/movements" -Headers $adminHeaders -Method Get
    if(@($manualMovements).Count -ne 1 -or @($manualMovements)[0].valorMovimiento -ne @($movements)[0].valorMovimiento -or @($manualMovements)[0].numeroLote -ne 'LOTE-P5-001' -or @($manualMovements)[0].fechaVencimiento -ne '2027-08-20'){ throw 'La entrada manual no produjo el mismo costo o no conservo lote y vencimiento.' }
    $serials=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/serialized-units" -Headers $adminHeaders -Method Get
    if(@($serials).Count -ne 2 -or 'MOT-P5-001' -notin $serials.motor -or 'CHA-P5-001' -notin $serials.chasis){ throw 'La captura manual no conservo motor y chasis.' }

    $accountingPeriods=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/accounting-periods" -Headers $adminHeaders -Method Get
    $accounts=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/accounting-accounts" -Headers $adminHeaders -Method Get
    if(@($accountingPeriods).Count -ne 1 -or @($accounts).Count -ne 4){ throw 'La API no publico los periodos y cuentas contables de la empresa.' }
    $accountingPeriodId=[long](@($accountingPeriods)[0].periodoContableId)
    $mixedBody=@{
        proveedorIdentificacion='890301886';proveedorRazonSocial='Proveedor API QA';tipoDocumento='FACTURA';numeroDocumento='FV-MIXTA-P6';fechaDocumento='2026-08-20';fechaVencimiento='2026-09-19';condicionPago='CREDITO';diasCredito=30;crearArticulosFaltantes=$false;moneda='COP';
        cufeCude=$null;fuente='MANUAL';subtotalBruto=150;descuentoTotal=15;impuestoTotal=25.65;cargoTotal=0;totalPagar=156.65;xmlOriginal=$null;documentoGuid=[guid]::NewGuid();
        lineas=@(
            @{numeroLinea=1;articuloId=[long]$articleSaved.id;codigoExterno='MOTO-P6';descripcion='Mercancia factura mixta';clasificacion='INVENTARIO';cantidad=1;unidadMedidaId=$unitId;factorAUnidadBase=1;precioUnitario=50;subtotalBruto=50;descuento=5;impuesto=8.55;retencion=0;cargo=0;totalNeto=45;numeroLote='LOTE-P6-001';fechaVencimiento='2027-08-20';seriales=@(@{numeroUnidad=1;serial='SER-P6-001';motor='MOT-P6-001';chasis='CHA-P6-001';vin='VIN-P6-001';color='AZUL';modelo='2027';informacionOriginal='SER-P6-001'})},
            @{numeroLinea=2;articuloId=[long]$serviceSaved.id;codigoExterno='SERV-P6';descripcion='Mantenimiento factura mixta';clasificacion='SERVICIO_GASTO';cantidad=1;unidadMedidaId=$unitId;factorAUnidadBase=1;precioUnitario=100;subtotalBruto=100;descuento=10;impuesto=17.1;retencion=4;cargo=0;totalNeto=90;numeroLote=$null;fechaVencimiento=$null;seriales=@()}
        )
    }
    $mixedCreated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($mixedBody|ConvertTo-Json -Depth 9)
    $mixedPrepared=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($mixedCreated.documentoProveedorId)/prepare" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=$warehouseId;periodoInventarioId=$periodId;fechaContable='2026-08-20';numeroRecepcion='ENT-FV-MIXTA-P6';numeroCausacion='CAU-FV-MIXTA-P6'}|ConvertTo-Json)
    if($null -eq $mixedPrepared.recepcionMercanciaId -or $null -eq $mixedPrepared.causacionServicioId -or $mixedPrepared.lineasInventario -ne 1 -or $mixedPrepared.lineasServicio -ne 1){ throw 'La factura mixta no se separo en recepcion y causacion.' }
    $accrual=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/service-accruals/$($mixedPrepared.causacionServicioId)" -Headers $adminHeaders -Method Get
    if($accrual.base -ne 90 -or $accrual.impuestos -ne 17.1 -or $accrual.retenciones -ne 4 -or $accrual.porPagar -ne 103.1 -or @($accrual.lineas).Count -ne 1){ throw 'La causacion no conservo base, impuesto, retencion o cuenta por pagar.' }
    $mixedBefore=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($mixedPrepared.recepcionMercanciaId)/movements" -Headers $adminHeaders -Method Get
    if($null -ne $mixedBefore -and @($mixedBefore).Count -ne 0){ throw 'Preparar la factura mixta afecto Kardex antes de confirmar.' }
    $assigned=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/service-accruals/$($mixedPrepared.causacionServicioId)/accounts" -Headers $adminHeaders -Method Put -ContentType 'application/json' -Body (@{centroCostoCodigo='TALLER';proyectoCodigo='P6-ERP';lineas=@(@{numeroLinea=2;cuentaContableCodigo='513595'})}|ConvertTo-Json -Depth 5)
    if($assigned.estado -ne 'VALIDADA'){ throw 'La asignacion de cuentas no valido la causacion.' }
    $servicePosted=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/service-accruals/$($mixedPrepared.causacionServicioId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoContableId=$accountingPeriodId;cuentaImpuestoCodigo='240810';cuentaRetencionCodigo='236525';cuentaPorPagarCodigo='220505';correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    $servicePostedAgain=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/service-accruals/$($mixedPrepared.causacionServicioId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoContableId=$accountingPeriodId;cuentaImpuestoCodigo='240810';cuentaRetencionCodigo='236525';cuentaPorPagarCodigo='220505';correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    if($servicePosted.estado -ne 'CONTABILIZADA' -or -not $servicePostedAgain.yaExistia){ throw 'La causacion no fue contabilizada de forma idempotente.' }
    $mixedReceiptPosted=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($mixedPrepared.recepcionMercanciaId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    if($mixedReceiptPosted.movimientos -ne 1){ throw 'La parte de mercancia de la factura mixta no genero exactamente un movimiento.' }
    $accrualPosted=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/service-accruals/$($mixedPrepared.causacionServicioId)" -Headers $adminHeaders -Method Get
    $debits=($accrualPosted.comprobanteLineas|Measure-Object -Property debito -Sum).Sum; $credits=($accrualPosted.comprobanteLineas|Measure-Object -Property credito -Sum).Sum
    if($accrualPosted.estado -ne 'CONTABILIZADA' -or $debits -ne 107.1 -or $credits -ne 107.1 -or $accrualPosted.centroCostoCodigo -ne 'TALLER' -or $accrualPosted.proyectoCodigo -ne 'P6-ERP'){ throw 'El comprobante de servicios no quedo balanceado o perdio sus dimensiones.' }
    $mixedWorkflow=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($mixedCreated.documentoProveedorId)" -Headers $adminHeaders -Method Get
    if($mixedWorkflow.estado -ne 'CONTABILIZADO' -or $mixedWorkflow.recepcionEstado -ne 'CONTABILIZADA' -or $mixedWorkflow.causacionEstado -ne 'CONTABILIZADA'){ throw 'El documento mixto no cerro ambos flujos.' }

    $stock=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/stock?q=MOTO-API" -Headers $adminHeaders -Method Get
    $kardex=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/kardex?desde=2026-08-01&hasta=2026-08-31&q=FV" -Headers $adminHeaders -Method Get
    $serialSearch=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/serialized-units?q=MOT-P4-001" -Headers $adminHeaders -Method Get
    $expiry=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/expiry-alerts?dias=730" -Headers $adminHeaders -Method Get
    if(@($stock).Count -lt 3 -or @($kardex).Count -lt 3 -or @($serialSearch).Count -ne 1 -or @($serialSearch)[0].chasis -ne 'CHA-P4-001' -or @($expiry).Count -lt 2){ throw 'Las consultas de existencias, Kardex, seriales o vencimientos no devolvieron la trazabilidad esperada.' }
    $supplierSources=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-returns/sources?q=FV-POINT4" -Headers $adminHeaders -Method Get
    $salesSources=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/sales-returns/sources" -Headers $adminHeaders -Method Get
    if(@($supplierSources).Count -ne 1 -or ($null -ne $salesSources -and @($salesSources).Count -ne 0)){ throw 'Las fuentes disponibles para devoluciones no son correctas.' }
    $destinationId=[long](@($warehouses)|Where-Object codigo -eq 'BOD-API-2'|Select-Object -First 1).bodegaId
    $transferBody=@{numero='TR-POINT7';bodegaOrigenId=$warehouseId;bodegaTransitoId=$null;bodegaDestinoId=$destinationId;fechaSalida='2026-08-21T10:00:00';lineas=@(@{articuloId=[long]$articleSaved.id;loteId=$null;cantidad=1;unidadSerializadaIds=@([long]@($serialSearch)[0].unidadSerializadaId)})}|ConvertTo-Json -Depth 6
    $transfer=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/transfers" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $transferBody
    $transferRepeated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/transfers" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $transferBody
    if($transfer.documentoId -ne $transferRepeated.documentoId -or -not $transferRepeated.yaExistia){ throw 'La creación del traslado no fue idempotente.' }
    $dispatched=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/transfers/$($transfer.documentoId)/dispatch" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoInventarioId=$periodId;fechaContable='2026-08-21';fechaRecepcion=$null}|ConvertTo-Json)
    $received=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/transfers/$($transfer.documentoId)/receive" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoInventarioId=$periodId;fechaContable='2026-08-21';fechaRecepcion='2026-08-21T12:00:00'}|ConvertTo-Json)
    $movedSerial=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/serialized-units?q=MOT-P4-001" -Headers $adminHeaders -Method Get
    if($dispatched.estado -ne 'DESPACHADO' -or $received.estado -ne 'RECIBIDO' -or @($movedSerial)[0].bodegaActualId -ne $destinationId -or @($movedSerial)[0].estado -ne 'DISPONIBLE'){ throw 'El traslado no conservó el estado, la bodega y la trazabilidad de la unidad serializada.' }

    $costConcepts=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/concepts" -Headers $adminHeaders -Method Get
    $costSources=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/landed/sources?q=FV-POINT4" -Headers $adminHeaders -Method Get
    if(@($costConcepts).Count -ne 1 -or @($costSources).Count -ne 1){ throw 'La API no publicó conceptos o recepciones objetivo para costos de adquisición.' }
    $landedBody=@{conceptoCostoId=[long]@($costConcepts)[0].conceptoCostoId;terceroId=[long]$supplierSaved.id;numeroSoporte='FLETE-POINT8';fechaDocumento='2026-08-22';moneda='COP';valorDistribuible=1000;metodo='CANTIDAD';lineas=@(@{recepcionMercanciaLineaId=[long]@($costSources)[0].recepcionMercanciaLineaId;baseManual=$null;porcentajeManual=$null;valorManual=$null})}|ConvertTo-Json -Depth 6
    $landed=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/landed" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $landedBody
    $landedRepeated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/landed" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $landedBody
    if($landed.distribucionCostoId -ne $landedRepeated.distribucionCostoId -or -not $landedRepeated.yaExistia){ throw 'El costo adicional no fue creado idempotentemente.' }
    $landedApplied=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/landed-cost-distributions/$($landed.distribucionCostoId)/apply" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoInventarioId=$periodId;fechaContable='2026-08-22'}|ConvertTo-Json)
    $landedAppliedAgain=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/landed-cost-distributions/$($landed.distribucionCostoId)/apply" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoInventarioId=$periodId;fechaContable='2026-08-22'}|ConvertTo-Json)
    if($landedApplied.movimientos -ne 1 -or -not $landedAppliedAgain.yaExistia){ throw 'El costo tardío no ajustó el inventario o no fue idempotente.' }
    $landedList=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/landed" -Headers $adminHeaders -Method Get
    if(@($landedList)[0].estado -ne 'APLICADA' -or @($landedList)[0].valorTotal -ne 1000){ throw 'La distribución aplicada no conserva su valor y estado.' }

    $group=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/groups" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{codigo='MOTOS';nombre='Motocicletas';naturalezaUso='Inventario para comercializacion'}|ConvertTo-Json)
    $book=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/books" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{codigo='GERENCIAL';nombre='Costo gerencial';categoria='GERENCIAL';formulaValoracion='PROMEDIO_PERIODICO';esPrincipal=$false}|ConvertTo-Json)
    $policy=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/policies" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{libroCostoId=[long]$book.libroCostoId;grupoInventarioId=[long]$group.grupoInventarioId;formulaValoracion='PROMEDIO_PERIODICO';vigenteDesde='2026-08-01';vigenteHasta=$null;motivoCambio='Politica gerencial inicial'}|ConvertTo-Json)
    $books=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/costs/books" -Headers $adminHeaders -Method Get
    $managerialBook=@($books|Where-Object codigo -eq 'GERENCIAL'|Select-Object -First 1)[0]
    if($null -eq $managerialBook -or $managerialBook.libroCostoId -ne $book.libroCostoId -or $policy.libroCostoId -ne $book.libroCostoId -or $policy.grupoInventarioId -ne $group.grupoInventarioId -or $policy.formulaValoracion -ne 'PROMEDIO_PERIODICO'){ throw 'El libro o la política de valoración no quedaron configurados.' }

    $netValues=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/net-values" -Headers $adminHeaders -Method Get
    $netItem=@($netValues|Where-Object articuloId -eq $articleSaved.id|Where-Object costoHistorico -gt 100|Select-Object -First 1)[0]
    $impairment=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/impairments" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=[long]$netItem.bodegaId;articuloId=[long]$netItem.articuloId;periodoInventarioId=$periodId;tipo='DETERIORO';valorNetoRealizable=[decimal]$netItem.costoHistorico-100;motivo='Prueba controlada de deterioro punto ocho';documentoSoporte='DET-P8';deterioroRelacionadoId=$null}|ConvertTo-Json)
    $impairmentReverse=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/impairments" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=[long]$netItem.bodegaId;articuloId=[long]$netItem.articuloId;periodoInventarioId=$periodId;tipo='REVERSA';valorNetoRealizable=100;motivo='Reversion controlada del deterioro punto ocho';documentoSoporte='REV-DET-P8';deterioroRelacionadoId=[long]$impairment.deterioroInventarioId}|ConvertTo-Json)
    if($impairment.deterioroAcumulado -ne 100 -or $impairmentReverse.deterioroAcumulado -ne 0 -or $impairmentReverse.costoHistorico -ne $netItem.costoHistorico){ throw 'El deterioro o su reversión alteraron el costo histórico.' }

    $masterArticles=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/master-data/articles" -Headers $adminHeaders -Method Get
    $negativeArticle=@($masterArticles|Where-Object codigo -eq 'ART-API'|Select-Object -First 1)[0]
    $negativeBody=@{bodegaId=$warehouseId;articuloId=[long]$negativeArticle.articuloId;periodoInventarioId=$periodId;fechaMovimiento='2026-08-23T09:00:00';fechaContable='2026-08-23';tipoDocumentoOrigen='ORDEN_SALIDA';documentoOrigenId=8001;numeroDocumento='NEG-P8';cantidadSolicitada=2;motivo='Salida excepcional autorizada por continuidad operativa';idempotencyKey=[guid]::NewGuid()}|ConvertTo-Json
    $negative=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/negative-exceptions" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $negativeBody
    if($negative.estado -ne 'PENDIENTE' -or $negative.cantidadValorizada -ne 0 -or $negative.cantidadPendiente -ne 2){ throw 'La salida excepcional asignó un costo ficticio o no quedó pendiente.' }
    $negativeDocument=@{proveedorIdentificacion='890301886';proveedorRazonSocial='Proveedor API QA';tipoDocumento='FACTURA';numeroDocumento='FV-NEG-P8';fechaDocumento='2026-08-23';fechaVencimiento='2026-09-22';condicionPago='CREDITO';diasCredito=30;crearArticulosFaltantes=$false;moneda='COP';cufeCude=$null;fuente='MANUAL';subtotalBruto=100;descuentoTotal=0;impuestoTotal=19;cargoTotal=0;totalPagar=119;xmlOriginal=$null;documentoGuid=[guid]::NewGuid();lineas=@(@{numeroLinea=1;articuloId=[long]$negativeArticle.articuloId;codigoExterno='ART-API';descripcion='Articulo regularizacion';clasificacion='INVENTARIO';cantidad=2;unidadMedidaId=$unitId;factorAUnidadBase=1;precioUnitario=50;subtotalBruto=100;descuento=0;impuesto=19;retencion=0;cargo=0;totalNeto=100;numeroLote=$null;fechaVencimiento=$null;seriales=@()})}
    $negativeCreated=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($negativeDocument|ConvertTo-Json -Depth 8)
    $negativePrepared=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/supplier-documents/$($negativeCreated.documentoProveedorId)/prepare" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=$warehouseId;periodoInventarioId=$periodId;fechaContable='2026-08-23';numeroRecepcion='ENT-NEG-P8';numeroCausacion=$null}|ConvertTo-Json)
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/receipts/$($negativePrepared.recepcionMercanciaId)/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{correlationId=[guid]::NewGuid()}|ConvertTo-Json)
    $negativeSources=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/negative-exceptions/$($negative.salidaExcepcionalNegativaId)/regularization-sources" -Headers $adminHeaders -Method Get
    $regularized=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/negative-exceptions/$($negative.salidaExcepcionalNegativaId)/regularize" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{recepcionMercanciaLineaId=[long]@($negativeSources)[0].recepcionMercanciaLineaId;periodoInventarioId=$periodId;fechaContable='2026-08-23'}|ConvertTo-Json)
    if($regularized.estado -ne 'REGULARIZADA'){ throw 'La salida negativa no se regularizó contra el costo real de la recepción.' }

    $count=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/physical-counts" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{numero='CF-POINT8';bodegaId=$warehouseId;fechaCorte='2026-08-24T18:00:00'}|ConvertTo-Json)
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/physical-counts/$($count.conteoFisicoId)/start" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body '{}'
    $countLines=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/physical-counts/$($count.conteoFisicoId)/lines" -Headers $adminHeaders -Method Get
    foreach($line in @($countLines)){ Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/physical-count-lines/$($line.conteoFisicoLineaId)/captures" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{numeroConteo=1;cantidadContada=$line.existenciaTeorica}|ConvertTo-Json)|Out-Null }
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/physical-counts/$($count.conteoFisicoId)/review" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body '{}'
    $approvals=@($countLines|ForEach-Object {@{conteoFisicoLineaId=[long]$_.conteoFisicoLineaId;cantidadAprobada=[decimal]$_.existenciaTeorica}})
    $approved=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/physical-counts/$($count.conteoFisicoId)/approve" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{lineas=$approvals}|ConvertTo-Json -Depth 5)
    $countApplied=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/physical-counts/$($count.conteoFisicoId)/apply" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoInventarioId=$periodId;fechaContable='2026-08-24'}|ConvertTo-Json)
    if($approved.estado -ne 'APROBADO' -or $countApplied.estado -ne 'APLICADO' -or $countApplied.movimientos -ne 0){ throw 'El conteo sin diferencias editó saldos o no completó su ciclo formal.' }
    $reconciliation=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/reconcile" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=$null;articuloId=$null}|ConvertTo-Json)
    $audits=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/audit" -Headers $adminHeaders -Method Get
    $reversible=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/reversible-movements" -Headers $adminHeaders -Method Get
    if($reconciliation.estado -ne 'CUADRADO' -or @($audits).Count -lt 8 -or @($reversible).Count -lt 1){ throw 'La conciliación, auditoría o consulta de reversas no quedó disponible.' }
    Assert-Status { Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/inventory/movements/1/reverse" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{periodoInventarioId=1;fechaContable='2026-08-20';motivo='corto';idempotencyKey=[guid]::NewGuid()}|ConvertTo-Json) } 400 'La validacion HTTP de reversa no funciono.'

    $viewerLogin=Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body (@{correo='consulta.api@qa.local';password=$viewerPassword}|ConvertTo-Json)
    $viewerHeaders=@{Authorization="Bearer $($viewerLogin.token)"}
    $null=Invoke-RestMethod -Uri "$baseUrl/api/v1/companies/$companyId/inventory/balances" -Headers $viewerHeaders -Method Get
    Assert-Status { Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/security/users" -Headers $viewerHeaders -Method Get } 403 'La administración de seguridad no bloqueó al usuario restringido.'
    Assert-Status { Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/master-data/suppliers" -Headers $viewerHeaders -Method Post -ContentType 'application/json' -Body (@{tipoIdentificacion='NIT';numeroIdentificacion='1';razonSocial='Sin permiso'}|ConvertTo-Json) } 403 'El permiso de maestros no bloqueo al usuario restringido.'
    $entryBody=@{
        bodegaId=0;ubicacionId=$null;articuloId=0;loteId=$null;periodoInventarioId=0;fechaMovimiento='2026-08-20T10:00:00';fechaContable='2026-08-20';
        tipoMovimiento='COMPRA';moduloOrigen='QA';tipoDocumentoOrigen='QA';documentoOrigenId=1;documentoLineaOrigenId=$null;numeroDocumento='QA';terceroId=$null;
        cantidad=1;costoUnitario=1;idempotencyKey=[guid]::NewGuid();usuarioId=$null;correlationId=$null;movimientoRelacionadoId=$null
    }|ConvertTo-Json
    Assert-Status { Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/$companyId/inventory/entries" -Headers $viewerHeaders -Method Post -ContentType 'application/json' -Body $entryBody } 403 'El permiso de entrada no bloqueo al usuario restringido.'
    Assert-Status { Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/999999/inventory/balances" -Headers $adminHeaders -Method Get } 403 'El aislamiento por empresa no rechazo una empresa ajena.'

    Write-Host 'QA API correcto: puntos 1 a 9, salud operativa, costos, controles e integracion Outbox sin duplicar ni editar Kardex.'
}
finally {
    if($apiProcess -and -not $apiProcess.HasExited){ Stop-Process -Id $apiProcess.Id -Force -ErrorAction SilentlyContinue; $apiProcess.WaitForExit() }
    if($null -eq $oldConnection){ Remove-Item Env:ConnectionStrings__NexoErp -ErrorAction SilentlyContinue } else { $env:ConnectionStrings__NexoErp=$oldConnection }
    $dropSql="IF DB_ID(N'$databaseName') IS NOT NULL BEGIN ALTER DATABASE [$safeDatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$safeDatabaseName]; END;"
    & sqlcmd -S $Instance -E -b -Q $dropSql | Out-Null
    Remove-Item -LiteralPath $outputLog,$errorLog -Force -ErrorAction SilentlyContinue
}
