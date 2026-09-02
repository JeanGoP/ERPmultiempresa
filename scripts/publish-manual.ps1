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

New-Item -ItemType Directory -Force -Path $publishRoot | Out-Null

dotnet publish (Join-Path $projectRoot 'backend\NexoERP.Api\NexoERP.Api.csproj') -c $Configuration -o $publishRoot --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Fallo la publicacion de la API.' }

$publishedSettings = Get-ChildItem -LiteralPath $publishRoot -Filter 'appsettings*.json' -File -ErrorAction SilentlyContinue
if ($publishedSettings) {
    throw 'La publicación contiene appsettings. Las cadenas de conexión de producción deben permanecer únicamente en el servidor.'
}

Write-Host "Backend publicado en $publishRoot"
