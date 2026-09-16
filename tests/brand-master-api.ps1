$brandsUrl="$baseUrl/api/v1/companies/$companyId/master-data/brands"
$brands=Invoke-RestMethod -Uri $brandsUrl -Headers $adminHeaders
$xmlBrand=@($brands)|Where-Object nombre -eq 'MARCA XML QA'
if(-not $xmlBrand -or $xmlBrand.referencias -ne 1){throw 'Falta la marca y su referencia en el maestro.'}
$recognition=@{descripciones=@('motocicleta  creada desde xml','Modelo que no existe')}|ConvertTo-Json
$matches=Invoke-RestMethod -Uri "$brandsUrl/recognize" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $recognition
if($matches[0].marca -ne 'MARCA XML QA' -or $matches[1].marca){throw 'Reconocimiento de líneas XML incorrecto.'}
$byCode=@{descripciones=@('Descripcion abreviada diferente','motocicleta creada desde xml');codigos=@('QA-XML','NO-EXISTE')}|ConvertTo-Json
$matchedCodes=Invoke-RestMethod -Uri "$brandsUrl/recognize" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $byCode
if($matchedCodes[0].marca -ne 'MARCA XML QA' -or $matchedCodes[1].marca -ne 'MARCA XML QA'){throw 'Falló la referencia exacta o la descripción de respaldo.'}
Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$brandsUrl/recognize" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body '{"descripciones":["x"],"codigos":[]}'} 400 'Se aceptaron códigos y descripciones desalineados.'
$brand=Invoke-RestMethod -Uri $brandsUrl -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body '{"nombre":"Marca nueva QA","activa":true}'
Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri $brandsUrl -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body '{"nombre":"MARCA NUEVA QA","activa":true}'} 409 'Se permitió duplicar una marca.'
$null=Invoke-RestMethod -Uri "$brandsUrl/$($brand.id)" -Headers $adminHeaders -Method Put -ContentType 'application/json' -Body '{"nombre":"Marca editada QA","activa":false}'
$freshBrands=Invoke-RestMethod -Uri $brandsUrl -Headers $adminHeaders
$updated=@($freshBrands)|Where-Object id -eq $brand.id
if($updated.nombre -ne 'Marca editada QA' -or $updated.activa){throw 'No se guardó la edición/estado de marca.'}
$null=Invoke-RestMethod -Uri "$brandsUrl/$($xmlBrand.id)" -Headers $adminHeaders -Method Put -ContentType 'application/json' -Body '{"nombre":"MARCA XML QA","activa":false}'
$matches=Invoke-RestMethod -Uri "$brandsUrl/recognize" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $recognition
if($matches[0].marca){throw 'El XML reconoció una marca desactivada.'}
$matchedCodes=Invoke-RestMethod -Uri "$brandsUrl/recognize" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $byCode
if($matchedCodes[0].marca){throw 'La referencia reconoció una marca desactivada.'}
$null=Invoke-RestMethod -Uri "$brandsUrl/$($xmlBrand.id)" -Headers $adminHeaders -Method Put -ContentType 'application/json' -Body '{"nombre":"MARCA XML QA","activa":true}'
Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri $brandsUrl -Headers $viewerHeaders -Method Post -ContentType 'application/json' -Body '{"nombre":"Sin permiso","activa":true}'} 403 'No se protegió la administración de marcas.'
Assert-Status {Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/v1/companies/999999/master-data/brands/recognize" -Headers $adminHeaders -Method Post -ContentType 'application/json' -Body $recognition} 403 'Se permitió reconocer marcas en una empresa ajena.'
Write-Host 'QA marcas: maestro, duplicados, edición, inactivación, reconocimiento XML y permisos correctos.'
