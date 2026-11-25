<#
.SYNOPSIS
Add Fira Code 6.2 ligatures to any monospaced TTF or OTF using native Windows FontForge.

.DESCRIPTION
Uses the Python bindings bundled with the FontForge Windows build. No Docker, WSL,
git submodules, or bash tools are needed. The output directory must be dedicated to
this build: every font in it is post-processed after ligaturization.

.PARAMETER FontPath
Input TTF or OTF font. Required for a build.

.PARAMETER OutputDir
Output directory, relative to the repo root or absolute. Defaults to fonts/output.

.PARAMETER LigatureFontFile
Font to copy ligatures from. Defaults to Fira Code 6.2, downloaded on first use.

.PARAMETER Prefix
Prepended to the family name. Defaults to Liga; pass an empty string to disable.

.PARAMETER OutputName
Replacement family name, useful when a licence requires renaming.

.PARAMETER CopyCharacterGlyphs
Also copy individual punctuation glyphs from Fira Code.

.PARAMETER FontForgePython
Path to ffpython.exe when FontForge is installed elsewhere.

.PARAMETER Help
Print this help text and exit.

.EXAMPLE
PS> .\build.ps1 -FontPath 'C:\Path\To\Font.ttf'

.EXAMPLE
PS> .\build.ps1 -FontPath 'C:\Path\To\Font.ttf' -OutputName 'MyFont Liga' -CopyCharacterGlyphs

.NOTES
fontTools must be installed into the bundled Python first; see README.md.
#>
[CmdletBinding()]
param(
    [string] $FontPath,

    [string] $OutputDir = 'fonts/output',
    [string] $LigatureFontFile = '',
    [string] $Prefix = 'Liga',
    [string] $OutputName = '',
    [switch] $CopyCharacterGlyphs,
    [string] $FontForgePython = 'C:\Program Files\FontForgeBuilds\bin\ffpython.exe',
    [switch] $Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Help) {
    Get-Help -Name $MyInvocation.MyCommand.Path -Full
    return
}

if (-not $FontPath) {
    throw "-FontPath is required. Run .\build.ps1 -Help for usage."
}

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path -LiteralPath $FontForgePython -PathType Leaf)) {
    throw "FontForge Python not found at '$FontForgePython'. Install the FontForge Windows build or pass -FontForgePython."
}

$font = (Resolve-Path -LiteralPath $FontPath -ErrorAction Stop).Path
if ($font -notmatch '\.(ttf|otf)$') {
    throw "Input font must be a .ttf or .otf file: $font"
}

$null = & $FontForgePython -c 'import fontTools' 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "fontTools is missing from the bundled Python. The bundled pip is broken; install with any working Python 3.11+:`n  python -m pip install --target (& '$FontForgePython' -c 'import site; print(site.getusersitepackages())') --no-binary fonttools fonttools"
}

if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $outDir = $OutputDir
} else {
    $outDir = Join-Path $repo $OutputDir
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $LigatureFontFile) {
    $firaDir = Join-Path $repo 'fonts/fira/distr/ttf'
    if (-not (Test-Path -LiteralPath (Join-Path $firaDir 'FiraCode-Regular.ttf') -PathType Leaf)) {
        $zipUrl = 'https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip'
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'ligaturizer-fira-6.2'
        $zipPath = Join-Path $tempRoot 'Fira_Code_v6.2.zip'
        try {
            New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
            Write-Host "Downloading Fira Code 6.2 TTFs from $zipUrl"
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
            $unpackDir = Join-Path $tempRoot 'unpacked'
            if (Test-Path -LiteralPath $unpackDir) {
                Remove-Item -LiteralPath $unpackDir -Recurse -Force
            }
            Expand-Archive -Path $zipPath -DestinationPath $unpackDir
            New-Item -ItemType Directory -Force -Path $firaDir | Out-Null
            Copy-Item -Path (Join-Path $unpackDir 'ttf/*.ttf') -Destination $firaDir
        } finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}

$ligaturizeScript = Join-Path $repo 'ligaturize.py'
$postprocessScript = Join-Path $repo 'postprocess.py'
$scriptArgs = @($font, "--output-dir=$outDir", "--prefix=$Prefix")
if ($LigatureFontFile) {
    $scriptArgs += "--ligature-font-file=$LigatureFontFile"
}
if ($OutputName) {
    $scriptArgs += "--output-name=$OutputName"
}
if ($CopyCharacterGlyphs) {
    $scriptArgs += '--copy-character-glyphs'
}

Push-Location $repo
try {
    & $FontForgePython $ligaturizeScript @scriptArgs
    if ($LASTEXITCODE -ne 0) {
        throw "ligaturize.py failed with exit code $LASTEXITCODE"
    }

    $outputs = @(Get-ChildItem -LiteralPath $outDir -File | Where-Object { $_.Extension -in '.ttf', '.otf' })
    foreach ($output in $outputs) {
        & $FontForgePython $postprocessScript $output.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "postprocess.py failed on $($output.FullName) with exit code $LASTEXITCODE"
        }
    }
} finally {
    Pop-Location
}

Write-Host "Done. Ligaturized fonts are in $outDir"
