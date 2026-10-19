param(
    [string]$DevEcoHome = 'D:\programs\DevEcoStudio',
    [switch]$TestOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$nodeExe = Join-Path $DevEcoHome 'tools\node\node.exe'
$hvigorCli = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
if (!(Test-Path -LiteralPath $nodeExe)) { throw "未找到 DevEco 内置 Node：$nodeExe" }
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
$env:NODE_HOME = Join-Path $DevEcoHome 'tools\node'
$env:Path = "$env:NODE_HOME;$env:JAVA_HOME\bin;$env:Path"
Push-Location $projectRoot
try {
    & $nodeExe --test tests/guidance.test.cjs
    if ($LASTEXITCODE -ne 0) { throw '路线逻辑测试失败' }
    if ($TestOnly) { return }
    & $nodeExe $hvigorCli --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw '鸿蒙工程编译失败' }
    $hap = Join-Path $projectRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'
    if (!(Test-Path -LiteralPath $hap)) { throw "未找到预期 HAP：$hap" }
    New-Item -ItemType Directory -Force -Path 'artifacts' | Out-Null
    Copy-Item -LiteralPath $hap -Destination 'artifacts\LaneAhead-0.1.0-unsigned.hap'
} finally {
    Pop-Location
}
