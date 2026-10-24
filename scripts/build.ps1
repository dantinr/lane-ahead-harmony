param(
    [string]$DevEcoHome = 'D:\programs\DevEcoStudio',
    [switch]$TestOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$nodeExe = Join-Path $DevEcoHome 'tools\node\node.exe'
$hvigorCli = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
if (Test-Path -LiteralPath $nodeExe) {
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
    $env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
    $env:NODE_HOME = Join-Path $DevEcoHome 'tools\node'
    $env:Path = "$env:NODE_HOME;$env:JAVA_HOME\bin;$env:Path"
} elseif ($TestOnly -and $env:LANEAHEAD_TYPESCRIPT) {
    $nodeExe = (Get-Command node -ErrorAction Stop).Source
} else {
    throw "未找到 DevEco 内置 Node：$nodeExe。请指定 -DevEcoHome；仅测逻辑可设置 LANEAHEAD_TYPESCRIPT 并使用 -TestOnly。"
}
Push-Location $projectRoot
try {
    & $nodeExe scripts/sync-version.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Version synchronization failed' }
    & $nodeExe scripts/prepare-local-config.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Local map configuration failed' }
    $version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
    & $nodeExe --test tests/guidance.test.cjs tests/route-planning.test.cjs tests/native-navigation.test.cjs tests/home-map.test.cjs tests/local-config.test.cjs tests/lane-preview.test.cjs tests/lane-sdk.test.cjs tests/lane-session.test.cjs tests/lane-collection.test.cjs
    if ($LASTEXITCODE -ne 0) { throw '路线逻辑测试失败' }
    if ($TestOnly) { return }
    & $nodeExe $hvigorCli --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw '鸿蒙工程编译失败' }
    $hap = Join-Path $projectRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
    if (!(Test-Path -LiteralPath $hap)) { throw "未找到预期 HAP：$hap" }
    New-Item -ItemType Directory -Force -Path 'artifacts' | Out-Null
    Copy-Item -LiteralPath $hap -Destination "artifacts\LaneAhead-$version-unsigned.hap"
    $signedHap = Join-Path $projectRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
    if (Test-Path -LiteralPath $signedHap) {
        Copy-Item -LiteralPath $signedHap -Destination "artifacts\LaneAhead-$version-signed.hap"
    }
} finally {
    Pop-Location
}
