param(
    [ValidateSet('Release','Debug')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$publishRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'publish'))
$expectedPublishRoot = [System.IO.Path]::GetFullPath("$projectRoot\publish")

if ($publishRoot -ne $expectedPublishRoot -or -not $publishRoot.StartsWith("$projectRoot\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "La ruta de publicación no es segura: $publishRoot"
}

if (Test-Path -LiteralPath $publishRoot) {
    Remove-Item -LiteralPath $publishRoot -Recurse -Force
}

$frontendTarget = Join-Path $publishRoot 'frontend'
$apiTarget = Join-Path $publishRoot 'api'
$databaseTarget = Join-Path $publishRoot 'database\migrations'
New-Item -ItemType Directory -Force -Path $frontendTarget,$apiTarget,$databaseTarget | Out-Null

dotnet publish (Join-Path $projectRoot 'backend\NexoERP.Api\NexoERP.Api.csproj') -c $Configuration -o $apiTarget --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Fallo la publicacion de la API.' }

Copy-Item -Path (Join-Path $projectRoot 'public\*') -Destination $frontendTarget -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot 'database\migrations\*.sql') -Destination $databaseTarget -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\manual-publishing.md') -Destination (Join-Path $publishRoot 'LEEME.md') -Force

$commit = (& git -C $projectRoot rev-parse --short HEAD).Trim()
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
@(
    "Nexo ERP - paquete de publicación manual"
    "Commit: $commit"
    "Configuración: $Configuration"
    "Generado: $generatedAt"
) | Set-Content -LiteralPath (Join-Path $publishRoot 'VERSION.txt') -Encoding utf8

Write-Host "Publicacion manual generada en $publishRoot"
Write-Host "Frontend: $frontendTarget"
Write-Host "API: $apiTarget"
Write-Host "Migraciones: $databaseTarget"
