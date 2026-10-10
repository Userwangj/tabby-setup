# 把整个 tabby-setup 目录打包成【单个压缩包】，便于一次拷贝分发。
# 对方拿到一个文件，解压后双击 install.cmd 即可。
param([string]$OutDir = '')

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$parent    = Split-Path -Parent $RootDir
$name      = Split-Path -Leaf $RootDir
if (-not $OutDir) { $OutDir = $parent }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$out = Join-Path $OutDir ($name + '-portable.zip')

Write-Host ''
Write-Host '=================================================='
Write-Host ' 打包 tabby-setup 为单个压缩包'
Write-Host '=================================================='
Write-Host (" 源目录: $RootDir")
Write-Host (" 输出  : $out")
Write-Host ''

if (Test-Path $out) { Remove-Item $out -Force -ErrorAction SilentlyContinue }

$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($tar) {
    Push-Location $parent
    try {
        & tar.exe -a -cf $out --exclude "$name/.git" $name
        if ($LASTEXITCODE -ne 0) { throw "tar 打包失败（exit=$LASTEXITCODE）" }
    } finally { Pop-Location }
} else {
    Write-Host ' （未找到 tar.exe，改用 Compress-Archive，可能较慢且占内存）'
    Compress-Archive -Path $RootDir -DestinationPath $out -CompressionLevel Optimal
}

$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host ''
Write-Host (" 完成: $out  ($mb MB)")
Write-Host ' 把这一个文件拷给对方，解压后运行 install.cmd 即可。'
Write-Host '=================================================='
