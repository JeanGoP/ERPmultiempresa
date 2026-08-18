param(
  [Parameter(Mandatory = $true)][string]$InputXml,
  [Parameter(Mandatory = $true)][string]$OutputJson
)

$settings = [System.Xml.XmlReaderSettings]::new()
$settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$reader = [System.Xml.XmlReader]::Create($InputXml, $settings)
$document = [System.Xml.XmlDocument]::new()
$document.Load($reader)
$reader.Close()

function Get-ElementChildren([System.Xml.XmlElement]$Node) {
  return @($Node.ChildNodes | Where-Object NodeType -eq Element)
}
function Get-DirectText([System.Xml.XmlElement]$Node) {
  return (($Node.ChildNodes | Where-Object NodeType -in @('Text', 'CDATA') | ForEach-Object { $_.Value.Trim() } | Where-Object { $_ }) -join ' ')
}
function Get-ValueType([string]$Value) {
  if ($Value -match '^(true|false)$') { return 'booleano' }
  if ($Value -match '^-?\d+([.,]\d+)?$') { return 'numero' }
  if ($Value -match '^\d{4}-\d{2}-\d{2}(T.*)?$') { return 'fecha' }
  return 'texto'
}
function Add-RepeatedDescendants([System.Xml.XmlElement]$Node, $Set) {
  [void]$Set.Add($Node)
  foreach ($child in Get-ElementChildren $Node) { Add-RepeatedDescendants $child $Set }
}
function Flatten-Record([System.Xml.XmlElement]$Node) {
  $record = [ordered]@{}
  function Walk([System.Xml.XmlElement]$Current, [string]$Prefix) {
    foreach ($attribute in $Current.Attributes) {
      $key = if ($Prefix) { "$Prefix.@$($attribute.Name)" } else { "@$($attribute.Name)" }
      $record[$key] = $attribute.Value
    }
    $text = Get-DirectText $Current
    if ($text) { $record[$(if ($Prefix) { $Prefix } else { '#text' })] = $text }
    foreach ($child in Get-ElementChildren $Current) {
      $childPrefix = if ($Prefix) { "$Prefix.$($child.Name)" } else { $child.Name }
      Walk $child $childPrefix
    }
  }
  Walk $Node ''
  return [pscustomobject]$record
}

$groups = [System.Collections.Generic.List[object]]::new()
$repeated = [System.Collections.Generic.HashSet[System.Xml.XmlElement]]::new()
function Find-Groups([System.Xml.XmlElement]$Parent, [string]$ParentPath) {
  foreach ($group in (Get-ElementChildren $Parent | Group-Object Name)) {
    $path = "$ParentPath/$($group.Name)"
    if ($group.Count -gt 1) {
      foreach ($node in $group.Group) { Add-RepeatedDescendants $node $repeated }
      $rows = @($group.Group | ForEach-Object { Flatten-Record $_ })
      $groups.Add([pscustomobject]@{ path = $path; name = $group.Name; rows = $rows })
    }
    foreach ($node in $group.Group) { Find-Groups $node $path }
  }
}
Find-Groups $document.DocumentElement "/$($document.DocumentElement.Name)"

$fields = [System.Collections.Generic.List[object]]::new()
function Collect-Fields([System.Xml.XmlElement]$Node, [string]$Path) {
  foreach ($attribute in $Node.Attributes) {
    $fields.Add([pscustomobject]@{ path = "$Path/@$($attribute.Name)"; value = $attribute.Value; type = 'atributo'; repeated = $repeated.Contains($Node) })
  }
  $text = Get-DirectText $Node
  if ($text) { $fields.Add([pscustomobject]@{ path = $Path; value = $text; type = Get-ValueType $text; repeated = $repeated.Contains($Node) }) }
  $children = Get-ElementChildren $Node
  $counts = @{}
  foreach ($child in $children) { $counts[$child.Name] = 1 + [int]$counts[$child.Name] }
  $indexes = @{}
  foreach ($child in $children) {
    $indexes[$child.Name] = 1 + [int]$indexes[$child.Name]
    $suffix = if ($counts[$child.Name] -gt 1) { "[$($indexes[$child.Name])]" } else { '' }
    Collect-Fields $child "$Path/$($child.Name)$suffix"
  }
}
Collect-Fields $document.DocumentElement "/$($document.DocumentElement.Name)"

$payload = [pscustomobject]@{
  documentTitle = [System.IO.Path]::GetFileName($InputXml)
  headers = @($fields | Where-Object { -not $_.repeated })
  details = @($groups)
  fields = @($fields)
}
$directory = Split-Path -Parent $OutputJson
if ($directory) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
[System.IO.File]::WriteAllText($OutputJson, ($payload | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))
Write-Output "Payload creado: $OutputJson"
