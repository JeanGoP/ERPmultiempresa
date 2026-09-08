# Executed inside api-smoke.ps1 against its disposable database only.
$originBase="$baseUrl/api/v1/companies/$companyId"
$originReceipts=@()
foreach($index in 1,2){
    $entryDate=if($index -eq 1){'2026-08-01'}else{'2026-08-10'}
    $originBody=@{}+$autoBody
    $originBody.numeroDocumento="FV-EDAD-$index";$originBody.cufeCude="CUFE-EDAD-$index";$originBody.documentoGuid=[guid]::NewGuid()
    $originBody.xmlOriginal="<Invoice><ID>FV-EDAD-$index</ID></Invoice>";$originBody.fechaDocumento=$entryDate;$originBody.fechaVencimiento=$entryDate
    $originBody.subtotalBruto=400;$originBody.impuestoTotal=0;$originBody.totalPagar=400
    $originBody.lineas=@(
        @{numeroLinea=1;articuloId=$null;codigoExterno='EDAD-SER';descripcion='Nevera serializada QA';clasificacion='INVENTARIO';cantidad=1;unidadCodigo='94';manejaSerial=$true;factorAUnidadBase=1;precioUnitario=100;subtotalBruto=100;descuento=0;impuesto=0;retencion=0;cargo=0;totalNeto=100;seriales=@(@{numeroUnidad=1;serial="EDAD-SER-$index"})},
        @{numeroLinea=2;articuloId=$null;codigoExterno='EDAD-PLANO';descripcion='Articulo por entrada QA';clasificacion='INVENTARIO';cantidad=3;unidadCodigo='94';manejaSerial=$false;factorAUnidadBase=1;precioUnitario=100;subtotalBruto=300;descuento=0;impuesto=0;retencion=0;cargo=0;totalNeto=300;seriales=@()}
    )
    $document=Invoke-RestMethod -Uri "$originBase/supplier-documents" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($originBody|ConvertTo-Json -Depth 10)
    $receipt=Invoke-RestMethod -Uri "$originBase/supplier-documents/$($document.documentoProveedorId)/prepare" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegaId=$warehouseId;periodoInventarioId=$periodId;fechaContable=$entryDate;numeroRecepcion="ENT-EDAD-$index"}|ConvertTo-Json)
    $rid=$receipt.recepcionMercanciaId;$originReceipts+=,$rid
    $distribution=Invoke-RestMethod -Uri "$originBase/receipts/$rid/distribution" -Headers $adminHeaders
    if(@($distribution).Count -ne 2){throw 'No se obtuvo una bodega por renglon.'}
    $assignments=@(@{recepcionMercanciaLineaId=$distribution[0].recepcionMercanciaLineaId;bodegaId=$warehouseId},@{recepcionMercanciaLineaId=$distribution[1].recepcionMercanciaLineaId;bodegaId=$destinationId})
    Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$originBase/receipts/$rid/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegas=@($assignments[0],$assignments[0])}|ConvertTo-Json -Depth 5)} 409 'Se aceptaron lineas repetidas en la distribucion.'
    $invalid=@{recepcionMercanciaLineaId=$distribution[1].recepcionMercanciaLineaId;bodegaId=999999}
    Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$originBase/receipts/$rid/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegas=@($assignments[0],$invalid)}|ConvertTo-Json -Depth 5)} 409 'Se acepto una bodega ajena o inexistente.'
    $null=Invoke-RestMethod -Uri "$originBase/receipts/$rid/post" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body (@{bodegas=$assignments}|ConvertTo-Json -Depth 5)
    $age=Invoke-RestMethod -Uri "$originBase/inventory/aging?recepcionId=$rid" -Headers $adminHeaders
    if(@($age).Count -ne 2 -or ($age|Where-Object codigo -eq 'EDAD-SER').bodegaId -ne $warehouseId -or ($age|Where-Object codigo -eq 'EDAD-PLANO').bodegaId -ne $destinationId -or @($age|Where-Object fechaEntrada -ne $entryDate).Count){throw 'La entrada no conservo la distribucion o su fecha contable original.'}
}
$rid=$originReceipts[1]
$beforePayable=Invoke-RestMethod -Uri "$originBase/accounts-payable" -Headers $adminHeaders
$operation=@{bodegaDestinoId=$warehouseId;periodoInventarioId=$periodId;fechaContable='2026-08-25';operacionGuid=[guid]::NewGuid()}
Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$originBase/receipts/$rid/transfer" -Headers $viewerHeaders -Method Post -ContentType 'application/json' -Body ($operation|ConvertTo-Json)} 403 'Un usuario de consulta pudo trasladar facturas.'
Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$originBase/receipts/999999/transfer" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($operation|ConvertTo-Json)} 409 'Se acepto una entrada ajena.'
$first=Invoke-RestMethod -Uri "$originBase/receipts/$rid/transfer" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($operation|ConvertTo-Json)
$repeat=Invoke-RestMethod -Uri "$originBase/receipts/$rid/transfer" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($operation|ConvertTo-Json)
if($first.traslados -ne 1 -or $repeat.traslados -ne 1){throw 'El traslado completo no fue idempotente.'}
$ageA=Invoke-RestMethod -Uri "$originBase/inventory/aging?recepcionId=$($originReceipts[0])" -Headers $adminHeaders
$ageB=Invoke-RestMethod -Uri "$originBase/inventory/aging?recepcionId=$rid" -Headers $adminHeaders
if(($ageA|Where-Object codigo -eq 'EDAD-PLANO').bodegaId -ne $destinationId -or @($ageB|Where-Object bodegaId -ne $warehouseId).Count -or @($ageB|Where-Object fechaEntrada -ne '2026-08-10').Count){throw 'Se traslado el origen equivocado o se reinicio la edad.'}
$operation.operacionGuid=[guid]::NewGuid();$operation.bodegaDestinoId=$destinationId
$null=Invoke-RestMethod -Uri "$originBase/receipts/$rid/transfer" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($operation|ConvertTo-Json)
$units=Invoke-RestMethod -Uri "$originBase/inventory/serialized-units?q=EDAD-SER-2" -Headers $adminHeaders
if($units[0].bodegaActualId -ne $destinationId){throw 'La unidad serializada no acompano al traslado completo.'}
$afterPayable=Invoke-RestMethod -Uri "$originBase/accounts-payable" -Headers $adminHeaders
if(($beforePayable|ConvertTo-Json -Depth 8 -Compress) -ne ($afterPayable|ConvertTo-Json -Depth 8 -Compress)){throw 'El traslado modifico la cartera del proveedor.'}

# Sell the newer serial deliberately: the older purchase must remain available.
$serialId=$units[0].unidadSerializadaId;$serialArticle=$units[0].articuloId
$saleSql=@"
EXEC sys.sp_set_session_context @key=N'BypassRls',@value=1;
DECLARE @Key uniqueidentifier=NEWID();
EXEC inv.usp_ContabilizarSalidaSerializada @EmpresaId=$companyId,@BodegaId=$destinationId,@ArticuloId=$serialArticle,@PeriodoInventarioId=$periodId,
@FechaMovimiento='2026-08-26',@FechaContable='2026-08-26',@TipoMovimiento='VENTA',@ModuloOrigen='QA',@TipoDocumentoOrigen='VENTA',@DocumentoOrigenId=44001,
@NumeroDocumento='QA-VENTA-EDAD',@CantidadSalida=1,@IdempotencyKey=@Key,@UnidadesJson=N'[$serialId]';
"@
& sqlcmd -S $Instance -E -b -d $databaseName -Q $saleSql
if($LASTEXITCODE -ne 0){throw 'Fallo la salida de prueba de la unidad mas nueva.'}
$operation.operacionGuid=[guid]::NewGuid();$operation.bodegaDestinoId=$warehouseId
Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$originBase/receipts/$rid/transfer" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($operation|ConvertTo-Json)} 409 'Se traslado parcialmente una factura con una unidad vendida.'
$remaining=Invoke-RestMethod -Uri "$originBase/inventory/aging?recepcionId=$rid" -Headers $adminHeaders
if(@($remaining).Count -ne 1 -or $remaining[0].codigo -ne 'EDAD-PLANO' -or $remaining[0].bodegaId -ne $destinationId -or $remaining[0].cantidad -ne 3){throw 'El rechazo no fue atomico o la edad incluye unidades vendidas.'}
$operation.operacionGuid=[guid]::NewGuid()
$null=Invoke-RestMethod -Uri "$originBase/receipts/$($originReceipts[0])/transfer" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body ($operation|ConvertTo-Json)
# Reapplying the migration must not duplicate changes or remove the extension.
& sqlcmd -S $Instance -E -b -d $databaseName -i (Join-Path $projectRoot 'database/migrations/044_receipt_warehouse_and_aging.sql')
if($LASTEXITCODE -ne 0){throw 'La migracion 044 no es reejecutable.'}
Write-Host 'QA origen: bodega por linea, seriales, factura exacta, traslado atomico, edad original, permisos y reintentos correctos.'
