param(
    [string]$DatabaseName = 'NexoErpDev',
    [string]$Instance = '(localdb)\MSSQLLocalDB'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tests = @(
    (Join-Path $projectRoot 'tests\sql\kardex-engine.sql'),
    (Join-Path $projectRoot 'tests\sql\tenant-isolation.sql'),
    (Join-Path $projectRoot 'tests\sql\granular-permissions.sql'),
    (Join-Path $projectRoot 'tests\sql\master-data-homologation.sql'),
    (Join-Path $projectRoot 'tests\sql\supplier-document-flow.sql'),
    (Join-Path $projectRoot 'tests\sql\purchase-payment-auto-items.sql'),
    (Join-Path $projectRoot 'tests\sql\landed-cost-allocation.sql'),
    (Join-Path $projectRoot 'tests\sql\receipt-posting.sql'),
    (Join-Path $projectRoot 'tests\sql\service-accrual-accounting.sql'),
    (Join-Path $projectRoot 'tests\sql\transfer-workflow.sql'),
    (Join-Path $projectRoot 'tests\sql\supplier-return.sql'),
    (Join-Path $projectRoot 'tests\sql\sales-return.sql'),
    (Join-Path $projectRoot 'tests\sql\physical-count.sql'),
    (Join-Path $projectRoot 'tests\sql\negative-regularization.sql'),
    (Join-Path $projectRoot 'tests\sql\landed-cost-application.sql'),
    (Join-Path $projectRoot 'tests\sql\landed-cost-after-operations.sql'),
    (Join-Path $projectRoot 'tests\sql\inventory-period-close.sql'),
    (Join-Path $projectRoot 'tests\sql\serialized-receipt.sql'),
    (Join-Path $projectRoot 'tests\sql\serialized-unit-lifecycle.sql'),
    (Join-Path $projectRoot 'tests\sql\inventory-reversal.sql'),
    (Join-Path $projectRoot 'tests\sql\outbox-impairment.sql'),
    (Join-Path $projectRoot 'tests\sql\inventory-reconciliation.sql'),
    (Join-Path $projectRoot 'tests\sql\production-operations.sql')
)

foreach ($test in $tests) {
    Write-Host "Ejecutando $(Split-Path $test -Leaf)..."
    & sqlcmd -S $Instance -E -b -d $DatabaseName -i $test
    if ($LASTEXITCODE -ne 0) { throw "Falló la prueba $(Split-Path $test -Leaf)." }
}

Write-Host 'Pruebas SQL completadas correctamente.'
