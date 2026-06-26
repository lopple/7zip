param(
  [string]$ReleaseName = '7zip-26.01-lopple.2',
  [string]$OfficialInstallerUrl = 'https://github.com/ip7z/7zip/releases/download/26.01/7z2601-x64.exe',
  [string]$OfficialInstallerSha256 = 'D64A0468F5B5B0B0FC5B2188450BCD655B70809D97B1C4535F2884635094377D',
  [string]$VcVarsPath,
  [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$ProgressPreference = 'SilentlyContinue'

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

function Reset-DirectoryUnderRoot {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$true)]
    [string]$Root
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  Assert-UnderRoot -Path $fullPath -Root $Root
  if (Test-Path -LiteralPath $fullPath) {
    Write-Host "Remove directory: $fullPath"
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $fullPath | Out-Null
}

function Find-VcVars64 {
  param(
    [string]$OverridePath
  )

  if (-not [string]::IsNullOrEmpty($OverridePath)) {
    $resolved = Resolve-Path -LiteralPath $OverridePath
    return $resolved.Path
  }

  $candidates = New-Object 'System.Collections.Generic.List[string]'
  if ($env:VSINSTALLDIR) {
    [void]$candidates.Add((Join-Path $env:VSINSTALLDIR 'VC\Auxiliary\Build\vcvars64.bat'))
  }

  $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
  if (-not [string]::IsNullOrEmpty($programFilesX86)) {
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
      $vswhereArgs = @(
        '-latest',
        '-products',
        '*',
        '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property',
        'installationPath'
      )
      $formattedArgs = ($vswhereArgs | ForEach-Object { '[' + $_ + ']' }) -join ' '
      Write-Host "argv: [$vswhere] $formattedArgs"
      $installPath = (& $vswhere @vswhereArgs | Select-Object -First 1)
      if (-not [string]::IsNullOrEmpty($installPath)) {
        [void]$candidates.Add((Join-Path $installPath 'VC\Auxiliary\Build\vcvars64.bat'))
      }
    }
  }

  [void]$candidates.Add('E:\toolchains\vs2022-buildtools\VC\Auxiliary\Build\vcvars64.bat')
  [void]$candidates.Add('C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat')
  [void]$candidates.Add('C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat')
  [void]$candidates.Add('C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat')

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw 'Could not find vcvars64.bat'
}

function Invoke-NmakeTarget {
  param(
    [Parameter(Mandatory=$true)]
    [string]$VcVars,
    [Parameter(Mandatory=$true)]
    [string]$TargetDir
  )

  $makeCommand = '"' + $VcVars + '" >nul && nmake /A PLATFORM=x64'
  $cmdArgs = @(
    '/d',
    '/s',
    '/c',
    $makeCommand
  )
  $formattedArgs = ($cmdArgs | ForEach-Object { '[' + $_ + ']' }) -join ' '
  Write-Host "Build target: $TargetDir"
  Write-Host "argv: [cmd.exe] $formattedArgs"
  Push-Location -LiteralPath $TargetDir
  try {
    & cmd.exe @cmdArgs
    if ($LASTEXITCODE -ne 0) {
      throw "nmake failed in ${TargetDir}: exit code $LASTEXITCODE"
    }
  }
  finally {
    Pop-Location
  }
}

function Find-7ZipExe {
  $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    'C:\Program Files\7-Zip\7z.exe',
    'C:\Program Files (x86)\7-Zip\7z.exe'
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw 'Could not find 7z.exe to extract the official installer'
}

function Write-ReleaseNotes {
  param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$true)]
    [string]$ReleaseName,
    [Parameter(Mandatory=$true)]
    [string]$Commit
  )

  $text = @"
# $ReleaseName

Unofficial 7-Zip 26.01 custom Windows x64 build.

Changes in this custom build:
- Adds an option to open the destination folder after extraction.
- Applies the saved open-destination option to `Extract to "archive\"` from the Explorer context menu.
- Uses the existing split-destination setting to initialize the File Manager Copy dialog to the archive-name folder.
- Adds root folder duplication elimination to the File Manager Copy dialog for archive extraction.

Build:
- Source commit: $Commit
- Official 7-Zip language source: $OfficialInstallerUrl
- Official language source SHA-256: $OfficialInstallerSha256

This package includes installer helper scripts and upstream license documents.
"@

  [System.IO.File]::WriteAllText($Path, $text, [System.Text.Encoding]::UTF8)
}

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Resolve-Path -LiteralPath (Join-Path $scriptDir '..')
$buildRoot = Join-Path $repoRoot.Path 'build'
if (-not (Test-Path -LiteralPath $buildRoot)) {
  New-Item -ItemType Directory -Path $buildRoot | Out-Null
}
$buildRootResolved = Resolve-Path -LiteralPath $buildRoot

if (-not $NoBuild) {
  $vcVars = Find-VcVars64 -OverridePath $VcVarsPath
  $targets = @(
    'CPP\7zip\UI\Explorer',
    'CPP\7zip\UI\GUI',
    'CPP\7zip\Bundles\Fm'
  )
  foreach ($target in $targets) {
    $targetDir = Join-Path $repoRoot.Path $target
    Invoke-NmakeTarget -VcVars $vcVars -TargetDir $targetDir
  }
}

$officialRoot = Join-Path $buildRootResolved.Path 'official-2601'
Reset-DirectoryUnderRoot -Path $officialRoot -Root $buildRootResolved.Path
$officialInstaller = Join-Path $officialRoot '7z2601-x64.exe'
Write-Host "Download official installer: $OfficialInstallerUrl"
Invoke-WebRequest -Uri $OfficialInstallerUrl -OutFile $officialInstaller

$installerHash = (Get-FileHash -LiteralPath $officialInstaller -Algorithm SHA256).Hash
if (-not [String]::Equals($installerHash, $OfficialInstallerSha256, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Official installer hash mismatch: $installerHash"
}
Write-Host "Verified official installer SHA-256: $installerHash"

$officialExtractRoot = Join-Path $officialRoot 'extracted'
Reset-DirectoryUnderRoot -Path $officialExtractRoot -Root $buildRootResolved.Path
$sevenZip = Find-7ZipExe
$outputArg = "-o$officialExtractRoot"
$sevenZipArgs = @(
  'x',
  $officialInstaller,
  $outputArg,
  '-y'
)
$formatted7zArgs = ($sevenZipArgs | ForEach-Object { '[' + $_ + ']' }) -join ' '
Write-Host "argv: [$sevenZip] $formatted7zArgs"
& $sevenZip @sevenZipArgs
if ($LASTEXITCODE -ne 0) {
  throw "7z extraction failed: exit code $LASTEXITCODE"
}

$officialLangRoot = Join-Path $officialExtractRoot 'Lang'
if (-not (Test-Path -LiteralPath $officialLangRoot)) {
  throw "Official installer did not contain Lang directory: $officialLangRoot"
}

$stageRoot = Join-Path $buildRootResolved.Path 'stage\7zip-custom'
$stageScript = Join-Path $scriptDir 'stage-built-7zip.ps1'
$stageArgs = @(
  '-SourceLangRoot',
  $officialLangRoot,
  '-StageRoot',
  $stageRoot
)
$formattedStageArgs = ($stageArgs | ForEach-Object { '[' + $_ + ']' }) -join ' '
Write-Host "argv: [powershell] [-NoProfile] [-ExecutionPolicy] [Bypass] [-File] [$stageScript] $formattedStageArgs"
& powershell -NoProfile -ExecutionPolicy Bypass -File $stageScript @stageArgs
if ($LASTEXITCODE -ne 0) {
  throw "stage-built-7zip.ps1 failed: exit code $LASTEXITCODE"
}

$releaseRoot = Join-Path $buildRootResolved.Path 'release'
if (-not (Test-Path -LiteralPath $releaseRoot)) {
  New-Item -ItemType Directory -Path $releaseRoot | Out-Null
}

$zipPath = Join-Path $releaseRoot ($ReleaseName + '-windows-x64-custom.zip')
$shaPath = $zipPath + '.sha256'
$notesPath = Join-Path $releaseRoot ($ReleaseName + '-release-notes.md')
Remove-Item -LiteralPath $zipPath,$shaPath,$notesPath -Force -ErrorAction SilentlyContinue

Write-Host "Create release ZIP: $zipPath"
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
$zipFile = Get-Item -LiteralPath $zipPath
$shaText = $zipHash.Hash + '  ' + $zipFile.Name + [Environment]::NewLine
[System.IO.File]::WriteAllText($shaPath, $shaText, [System.Text.Encoding]::ASCII)

$commit = ''
try {
  $commit = (& git -C $repoRoot.Path rev-parse HEAD).Trim()
}
catch {
}
Write-ReleaseNotes -Path $notesPath -ReleaseName $ReleaseName -Commit $commit

Write-Host "Release ZIP: $zipPath"
Write-Host "Release SHA256: $shaPath"
Write-Host "Release notes: $notesPath"
Write-Host "ZIP SHA-256: $($zipHash.Hash)"
