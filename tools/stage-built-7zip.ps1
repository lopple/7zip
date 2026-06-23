param(
  [string]$SourceLangRoot = 'C:\Program Files\7-Zip\Lang',
  [string]$TranslationsPath,
  [string]$StageRoot,
  [switch]$NoClean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Find-LineIndex {
  param(
    [Parameter(Mandatory=$true)]
    $Lines,
    [Parameter(Mandatory=$true)]
    [string]$Marker
  )

  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ([string]$Lines[$i] -eq $Marker) {
      return $i
    }
  }
  throw "Could not find marker: $Marker"
}

function Find-NextNumericMarkerIndex {
  param(
    [Parameter(Mandatory=$true)]
    $Lines,
    [Parameter(Mandatory=$true)]
    [int]$StartIndex
  )

  for ($i = $StartIndex + 1; $i -lt $Lines.Count; $i++) {
    $line = ([string]$Lines[$i]).Trim()
    $numericValue = 0
    if ([int]::TryParse($line, [ref]$numericValue)) {
      return $i
    }
  }

  return $Lines.Count
}

function Get-NextLangIdBeforeIndex {
  param(
    [Parameter(Mandatory=$true)]
    $Lines,
    [Parameter(Mandatory=$true)]
    [int]$StartId,
    [Parameter(Mandatory=$true)]
    [int]$StartIndex,
    [Parameter(Mandatory=$true)]
    [int]$EndIndex
  )

  $currentId = $StartId
  for ($i = $StartIndex + 1; $i -lt $EndIndex; $i++) {
    $line = [string]$Lines[$i]
    $trimmed = $line.Trim()
    $numericValue = 0
    if ([int]::TryParse($trimmed, [ref]$numericValue)) {
      throw "Unexpected language marker before index ${EndIndex}: $trimmed"
    }

    $currentId++
  }

  return $currentId
}

function Update-LangFile {
  param(
    [Parameter(Mandatory=$true)]
    [string]$LangPath,
    [Parameter(Mandatory=$true)]
    [string]$CopyText,
    [Parameter(Mandatory=$true)]
    [string]$SettingsText,
    [Parameter(Mandatory=$true)]
    [string]$ExtractText
  )

  $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
  $text = [System.IO.File]::ReadAllText($LangPath, [System.Text.Encoding]::UTF8)
  $text = $text -replace "`r`n", "`n"
  $text = $text -replace "`r", "`n"
  $original = $text

  $lines = $text.Split([char]10)
  $list = New-Object 'System.Collections.Generic.List[string]'
  foreach ($line in $lines) {
    [void]$list.Add($line)
  }

  if (-not $list.Contains('104')) {
    $index401 = Find-LineIndex -Lines $list -Marker '401'
    $list.Insert($index401, '104')
    $list.Insert($index401 + 1, $CopyText)
  }

  if (-not $list.Contains($SettingsText)) {
    $index2500 = Find-LineIndex -Lines $list -Marker '2500'
    $index2900 = Find-NextNumericMarkerIndex -Lines $list -StartIndex $index2500
    $nextId = Get-NextLangIdBeforeIndex -Lines $list -StartId 2500 -StartIndex $index2500 -EndIndex $index2900
    while ($nextId -lt 2509) {
      $list.Insert($index2900, '')
      $index2900++
      $nextId++
    }
    if ($nextId -ne 2509) {
      throw "Unexpected settings insertion id in ${LangPath}: $nextId"
    }
    $list.Insert($index2900, $SettingsText)
  }

  if (-not $list.Contains($ExtractText)) {
    if ($list.Contains('3430')) {
      $index3430 = Find-LineIndex -Lines $list -Marker '3430'
      $index3440 = Find-NextNumericMarkerIndex -Lines $list -StartIndex $index3430
      $nextId = Get-NextLangIdBeforeIndex -Lines $list -StartId 3430 -StartIndex $index3430 -EndIndex $index3440
      while ($nextId -lt 3433) {
        $list.Insert($index3440, '')
        $index3440++
        $nextId++
      }
      if ($nextId -ne 3433) {
        throw "Unexpected extract insertion id in ${LangPath}: $nextId"
      }
      $list.Insert($index3440, $ExtractText)
    }
    else {
      $index3500 = Find-LineIndex -Lines $list -Marker '3500'
      $list.Insert($index3500, '3433')
      $list.Insert($index3500 + 1, $ExtractText)
    }
  }

  $updated = $list.ToArray() -join "`n"
  if ($updated -ne $original) {
    $updated = $updated -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($LangPath, $updated, $encoding)
  }
}

function Assert-UnderRoot {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$true)]
    [string]$Root
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($Root)
  $rootWithSlash = $fullRoot.TrimEnd('\') + '\'
  if (-not $fullPath.StartsWith($rootWithSlash, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing path outside root: $fullPath"
  }
}

function Copy-RequiredFile {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Source,
    [Parameter(Mandatory=$true)]
    [string]$Destination
  )

  $sourceResolved = Resolve-Path -LiteralPath $Source
  $destParent = Split-Path -Parent $Destination
  if (-not (Test-Path -LiteralPath $destParent)) {
    New-Item -ItemType Directory -Path $destParent | Out-Null
  }
  Copy-Item -LiteralPath $sourceResolved.Path -Destination $Destination -Force
}

function Write-TextFileAscii {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$true)]
    [string]$Text
  )
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::ASCII)
}

function Read-Translations {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Path
  )

  $resolved = Resolve-Path -LiteralPath $Path
  $json = [System.IO.File]::ReadAllText($resolved.Path, [System.Text.Encoding]::UTF8)
  $records = $json | ConvertFrom-Json
  $map = @{}
  foreach ($record in $records) {
    if ([string]::IsNullOrEmpty($record.file) -or
        [string]::IsNullOrEmpty($record.copy) -or
        [string]::IsNullOrEmpty($record.settings) -or
        [string]::IsNullOrEmpty($record.extract)) {
      throw "Invalid translation record in $($resolved.Path)"
    }
    $map[[string]$record.file] = [PSCustomObject]@{
      FileName = [string]$record.file
      CopyText = [string]$record.copy
      SettingsText = [string]$record.settings
      ExtractText = [string]$record.extract
    }
  }
  return $map
}

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Resolve-Path -LiteralPath (Join-Path $scriptDir '..')
if ([string]::IsNullOrEmpty($TranslationsPath)) {
  $TranslationsPath = Join-Path $scriptDir 'lang-extra-translations.json'
}
$buildRoot = Join-Path $repoRoot.Path 'build'
if (-not (Test-Path -LiteralPath $buildRoot)) {
  New-Item -ItemType Directory -Path $buildRoot | Out-Null
}
$buildRootResolved = Resolve-Path -LiteralPath $buildRoot

if ([string]::IsNullOrEmpty($StageRoot)) {
  $StageRoot = Join-Path $buildRootResolved.Path 'stage\7zip-custom'
}

$stageRootFull = [System.IO.Path]::GetFullPath($StageRoot)
Assert-UnderRoot -Path $stageRootFull -Root $buildRootResolved.Path

if ((Test-Path -LiteralPath $stageRootFull) -and -not $NoClean) {
  $existingStage = Resolve-Path -LiteralPath $stageRootFull
  Assert-UnderRoot -Path $existingStage.Path -Root $buildRootResolved.Path
  Write-Host "Remove stage: $($existingStage.Path)"
  Get-ChildItem -LiteralPath $existingStage.Path -Recurse -Force | ForEach-Object {
    if ($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
      $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }
  }
  Remove-Item -LiteralPath $existingStage.Path -Recurse -Force
}

$payloadRoot = Join-Path $stageRootFull '7-Zip'
$payloadLang = Join-Path $payloadRoot 'Lang'
New-Item -ItemType Directory -Path $payloadLang -Force | Out-Null

$binaries = @(
  [PSCustomObject]@{
    Name = '7-zip.dll'
    Source = Join-Path $repoRoot.Path 'CPP\7zip\UI\Explorer\x64\7-zip.dll'
    Destination = Join-Path $payloadRoot '7-zip.dll'
  },
  [PSCustomObject]@{
    Name = '7zG.exe'
    Source = Join-Path $repoRoot.Path 'CPP\7zip\UI\GUI\x64\7zG.exe'
    Destination = Join-Path $payloadRoot '7zG.exe'
  },
  [PSCustomObject]@{
    Name = '7zFM.exe'
    Source = Join-Path $repoRoot.Path 'CPP\7zip\Bundles\Fm\x64\7zFM.exe'
    Destination = Join-Path $payloadRoot '7zFM.exe'
  }
)

foreach ($binary in $binaries) {
  Write-Host "Stage binary: $($binary.Name)"
  Copy-RequiredFile -Source $binary.Source -Destination $binary.Destination
}

$sourceLangResolved = Resolve-Path -LiteralPath $SourceLangRoot
Write-Host "Stage language files from: $($sourceLangResolved.Path)"
$langSourceFiles = Get-ChildItem -LiteralPath $sourceLangResolved.Path -File | Where-Object {
  $_.Name -eq 'en.ttt' -or $_.Name.EndsWith('.txt', [StringComparison]::OrdinalIgnoreCase)
}
$langSourceFiles | ForEach-Object {
  $dest = Join-Path $payloadLang $_.Name
  Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
}

$translations = Read-Translations -Path $TranslationsPath
Write-Host "Translations: $TranslationsPath"

$missingTranslations = @()
Get-ChildItem -LiteralPath $payloadLang -File | ForEach-Object {
  if (-not $translations.ContainsKey($_.Name)) {
    $missingTranslations += $_.Name
  }
}
if ($missingTranslations.Count -ne 0) {
  throw ('Missing language translations: ' + ($missingTranslations -join ', '))
}

foreach ($translation in $translations.Values) {
  $langFile = Join-Path $payloadLang $translation.FileName
  if (Test-Path -LiteralPath $langFile) {
    Write-Host "Patch language file: $($translation.FileName)"
    Update-LangFile -LangPath $langFile -CopyText $translation.CopyText -SettingsText $translation.SettingsText -ExtractText $translation.ExtractText
  }
}

$installPs1 = @'
param(
  [string]$InstallRoot = 'C:\Program Files\7-Zip',
  [switch]$SkipExplorerRestart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-UnderRoot {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$true)]
    [string]$Root
  )
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($Root)
  $rootWithSlash = $fullRoot.TrimEnd('\') + '\'
  if (-not $fullPath.StartsWith($rootWithSlash, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing path outside root: $fullPath"
  }
}

function Quote-StartProcessArgument {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Value
  )

  if ($Value.Length -eq 0) {
    return '""'
  }
  if ($Value.IndexOfAny([char[]]@(' ', "`t", '"')) -lt 0) {
    return $Value
  }
  $escaped = $Value.Replace('"', '\"')
  return '"' + $escaped + '"'
}

if (-not (Test-IsAdmin)) {
  $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $scriptPath = $PSCommandPath
  $argsList = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $scriptPath,
    '-InstallRoot',
    $InstallRoot
  )
  if ($SkipExplorerRestart) {
    $argsList += '-SkipExplorerRestart'
  }
  $formattedArgs = ($argsList | ForEach-Object { '[' + $_ + ']' }) -join ' '
  $argumentString = ($argsList | ForEach-Object { Quote-StartProcessArgument -Value $_ }) -join ' '
  Write-Host "Requesting admin via UAC: [$psExe] $formattedArgs"
  Write-Host "Start-Process argument string: $argumentString"
  $process = Start-Process -FilePath $psExe -ArgumentList $argumentString -Verb RunAs -Wait -PassThru
  exit $process.ExitCode
}

$stageRoot = Split-Path -Parent $PSCommandPath
$payloadRoot = Join-Path $stageRoot '7-Zip'
$payloadLang = Join-Path $payloadRoot 'Lang'
$installResolved = Resolve-Path -LiteralPath $InstallRoot
$payloadResolved = Resolve-Path -LiteralPath $payloadRoot
$payloadLangResolved = Resolve-Path -LiteralPath $payloadLang

$logPath = Join-Path $stageRoot 'install.log'
$startLogPath = Join-Path $stageRoot 'install-start.log'
$errorLogPath = Join-Path $stageRoot 'install-error.log'
$transcriptStarted = $false
$explorerStopped = $false

Add-Content -LiteralPath $startLogPath -Value ('Started: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -Encoding ASCII

try {
  Start-Transcript -Path $logPath -Append | Out-Null
  $transcriptStarted = $true

  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupRoot = Join-Path $installResolved.Path ('backup-custom-' + $stamp)
  $backupLang = Join-Path $backupRoot 'Lang'
  New-Item -ItemType Directory -Path $backupLang -Force | Out-Null

  Write-Host "Install root: $($installResolved.Path)"
  Write-Host "Payload root: $($payloadResolved.Path)"
  Write-Host "Backup root: $backupRoot"

  $payloadFiles = Get-ChildItem -LiteralPath $payloadResolved.Path -File
  foreach ($payloadFile in $payloadFiles) {
    $target = Join-Path $installResolved.Path $payloadFile.Name
    if (Test-Path -LiteralPath $target) {
      $backup = Join-Path $backupRoot $payloadFile.Name
      Write-Host "Backup: $target -> $backup"
      Copy-Item -LiteralPath $target -Destination $backup -Force
    }
  }

  $installLang = Join-Path $installResolved.Path 'Lang'
  if (-not (Test-Path -LiteralPath $installLang)) {
    New-Item -ItemType Directory -Path $installLang | Out-Null
  }

  $payloadLangFiles = Get-ChildItem -LiteralPath $payloadLangResolved.Path -File
  foreach ($payloadLangFile in $payloadLangFiles) {
    $target = Join-Path $installLang $payloadLangFile.Name
    if (Test-Path -LiteralPath $target) {
      $backup = Join-Path $backupLang $payloadLangFile.Name
      Copy-Item -LiteralPath $target -Destination $backup -Force
    }
  }

  Write-Host 'Stopping 7-Zip UI processes'
  Stop-Process -Name 7zFM,7zG -Force -ErrorAction SilentlyContinue

  if (-not $SkipExplorerRestart) {
    Write-Host 'Stopping explorer.exe'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    $explorerStopped = $true
    Start-Sleep -Seconds 2
  }

  foreach ($payloadFile in $payloadFiles) {
    $target = Join-Path $installResolved.Path $payloadFile.Name
    Write-Host "Install: $($payloadFile.FullName) -> $target"
    Copy-Item -LiteralPath $payloadFile.FullName -Destination $target -Force
  }

  foreach ($payloadLangFile in $payloadLangFiles) {
    $target = Join-Path $installLang $payloadLangFile.Name
    Copy-Item -LiteralPath $payloadLangFile.FullName -Destination $target -Force
  }

  Write-Host 'Verify installed file hashes'
  foreach ($payloadFile in $payloadFiles) {
    $target = Join-Path $installResolved.Path $payloadFile.Name
    $sourceHash = Get-FileHash -LiteralPath $payloadFile.FullName -Algorithm SHA256
    $targetHash = Get-FileHash -LiteralPath $target -Algorithm SHA256
    if ($sourceHash.Hash -ne $targetHash.Hash) {
      throw "Hash mismatch after install: $($payloadFile.Name)"
    }
    Write-Host "OK: $($payloadFile.Name) $($targetHash.Hash)"
  }

  Write-Host 'Install completed.'
  Write-Host "Log: $logPath"
}
catch {
  $message = @(
    'Install failed.'
    ('Time: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    ('Error: ' + $_.Exception.Message)
    ('ScriptStackTrace: ' + $_.ScriptStackTrace)
    ''
  ) -join [Environment]::NewLine
  Add-Content -LiteralPath $errorLogPath -Value $message -Encoding ASCII
  throw
}
finally {
  if ($explorerStopped) {
    Write-Host 'Starting explorer.exe'
    Start-Process explorer.exe
  }
  if ($transcriptStarted) {
    Stop-Transcript | Out-Null
  }
}
'@

$installCmd = @'
@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Install-7Zip-Custom.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo Exit code: %EXIT_CODE%
pause
exit /b %EXIT_CODE%
'@

$readme = @'
7-Zip custom staging package

Double-click Install-7Zip-Custom.cmd to install this staged build.

Payload:
  7-Zip\7-zip.dll
  7-Zip\7zG.exe
  7-Zip\7zFM.exe
  7-Zip\Lang\*.txt

The installer backs up overwritten files under:
  C:\Program Files\7-Zip\backup-custom-YYYYMMDD-HHMMSS

It restarts explorer.exe unless Install-7Zip-Custom.ps1 is run with:
  -SkipExplorerRestart
'@

Write-TextFileAscii -Path (Join-Path $stageRootFull 'Install-7Zip-Custom.ps1') -Text $installPs1
Write-TextFileAscii -Path (Join-Path $stageRootFull 'Install-7Zip-Custom.cmd') -Text $installCmd
Write-TextFileAscii -Path (Join-Path $stageRootFull 'README.txt') -Text $readme

$manifestPath = Join-Path $stageRootFull 'manifest.txt'
$manifestLines = New-Object 'System.Collections.Generic.List[string]'
[void]$manifestLines.Add('7-Zip custom staging manifest')
[void]$manifestLines.Add(('Generated: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
[void]$manifestLines.Add(('StageRoot: ' + $stageRootFull))
[void]$manifestLines.Add('')
[void]$manifestLines.Add('Payload hashes:')
Get-ChildItem -LiteralPath $payloadRoot -File | Sort-Object Name | ForEach-Object {
  $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
  [void]$manifestLines.Add(($hash.Hash + '  ' + $_.Name))
}
[void]$manifestLines.Add('')
[void]$manifestLines.Add('Language file count:')
$langCount = @(Get-ChildItem -LiteralPath $payloadLang -File).Count
[void]$manifestLines.Add([string]$langCount)
[System.IO.File]::WriteAllLines($manifestPath, $manifestLines.ToArray(), [System.Text.Encoding]::ASCII)

Write-Host "Staged package: $stageRootFull"
Write-Host "Double-click: $(Join-Path $stageRootFull 'Install-7Zip-Custom.cmd')"
Write-Host "Manifest: $manifestPath"
