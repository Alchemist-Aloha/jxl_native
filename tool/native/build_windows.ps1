# Builds jxl_native.dll for one target into dist/<target>/.
# usage: tool/native/build_windows.ps1 <windows-x64|windows-arm64>
param([Parameter(Mandatory = $true)][string]$Target)
$ErrorActionPreference = 'Stop'
$Arch = @{ 'windows-x64' = 'x64'; 'windows-arm64' = 'ARM64' }[$Target]
if (-not $Arch) { throw "Unsupported target: $Target" }

$Root = (Resolve-Path "$PSScriptRoot/../..").Path
$Cache = if ($env:JXL_NATIVE_CACHE) { $env:JXL_NATIVE_CACHE } else { "$Root/.native-cache" }
$Source = "$Cache/sources/libjxl"
$Build = "$Cache/build/$Target"
$Dist = "$Root/dist/$Target"
$Info = (Get-Content "$Root/native/versions.json" | ConvertFrom-Json).libjxl

function Invoke-Git { git @args; if ($LASTEXITCODE -ne 0) { throw "git $args failed" } }

$Head = if (Test-Path "$Source/.git") { git -C $Source rev-parse HEAD } else { '' }
if ($Head -ne $Info.commit) {
  Remove-Item -Recurse -Force $Source -ErrorAction SilentlyContinue
  Invoke-Git clone --quiet --filter=blob:none --no-checkout $Info.repository $Source
  Invoke-Git -C $Source fetch --quiet --depth 1 origin $Info.commit
  Invoke-Git -C $Source checkout --quiet --detach $Info.commit
}
# Submodule commits are pinned by the libjxl commit itself.
Invoke-Git -C $Source submodule update --quiet --init --depth 1 @($Info.submodules)

Remove-Item -Recurse -Force $Build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Dist | Out-Null
cmake -S "$Root/native" -B $Build -A $Arch `
  "-DLIBJXL_SOURCE_DIR=$Source"
if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }
cmake --build $Build --config MinSizeRel --target jxl_native --parallel
if ($LASTEXITCODE -ne 0) { throw 'cmake build failed' }

$Library = Get-ChildItem $Build -Recurse -Filter jxl_native.dll | Select-Object -First 1
if (-not $Library) { throw 'Built library not found' }
Copy-Item $Library.FullName "$Dist/jxl_native.dll"

$Input = [IO.File]::OpenRead("$Dist/jxl_native.dll")
$Output = [IO.File]::Create("$Dist/jxl_native.dll.gz")
$Gzip = [IO.Compression.GZipStream]::new($Output, [IO.Compression.CompressionLevel]::SmallestSize)
try { $Input.CopyTo($Gzip) } finally { $Gzip.Dispose(); $Output.Dispose(); $Input.Dispose() }
Write-Output "$Dist/jxl_native.dll"
