# ============================================================
#  verify.ps1 - 进度显示自检（双击 verify.cmd 运行）
#  在真实控制台窗口里演示：
#    [1] 安装动画条（跑马灯）
#    [2] 真实下载的实时单行进度（需要网络）
#    [3] 本地流式演示（无网络也能看到持续刷新的进度行）
#  重要：请直接双击运行 / 在真实窗口里运行；
#        若把输出重定向到文件（> log.txt），会看到每帧各占一行，
#        这是重定向的正常现象，不是脚本问题。
# ============================================================
$ErrorActionPreference = 'Continue'
$RootDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'cache-lib.ps1')

Write-Host '=================================================='
Write-Host '  Tabby 安装器 - 进度显示自检 (verify)'
Write-Host '=================================================='

# ---- [1] 安装动画（跑马灯进度条，不是转圈）----
Write-Host ''
Write-Host '[1/3] 安装动画条（跑马灯，持续 5 秒）...'
Invoke-WithSpinner '正在演示安装动画' '安装动画正常' { Start-Sleep -Seconds 5 }

# ---- [2] 真实下载的实时进度 ----
Write-Host ''
Write-Host '[2/3] 真实下载实时进度（oh-my-posh 主题包，约 148 KB）...'
$tmp = Join-Path $env:TEMP 'verify-omp-themes.zip'
$ver  = 'v31.6.0'
$ok = $false
$vurls = @(
        "https://ghfast.top/https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$ver/themes.zip",
        "https://gh-proxy.com/https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$ver/themes.zip",
        "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/$ver/themes.zip")
if (Get-FileFromMirrors -Urls $vurls -OutFile $tmp -MinBytes 50KB -Activity 'verify 下载') { $ok = $true }
if ($ok) {
    Write-Host ('  真实下载：正常（' + [math]::Round((Get-Item $tmp).Length / 1KB, 1) + ' KB）')
} else {
    Write-Warning '  真实下载失败（可能无网络/镜像波动），继续本地演示'
}

# ---- [3] 离线包本地解压（确定性进度条）----
Write-Host ''
Write-Host '[3/3] 离线包本地解压（确定性进度条）...'
$zip = Join-Path (Join-Path $RootDir 'cache') 'node-win-x64.zip'
if (Test-Path $zip) {
    $dst = Join-Path $env:TEMP 'verify-extract'
    Expand-ZipWithProgress -ZipPath $zip -Destination $dst -Activity '解压 Node.js'
    Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host '  （未找到 cache\node-win-x64.zip，跳过本地解压演示）'
}

Write-Host ''
Write-Host '=================================================='
Write-Host ' 自检完成。判定标准：'
Write-Host '  [1] 安装步骤：进度条里的填充块来回移动（跑马灯，不是转圈）'
Write-Host '  [2] 下载：填充块/百分比/速度/ETA 在同一行实时推进'
Write-Host '  [3] 离线包解压：填充块按文件数稳步推进，直到 100%'
Write-Host '=================================================='
