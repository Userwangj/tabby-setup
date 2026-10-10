# 查看离线包下载进度（双击 scripts\progress.cmd 或运行本脚本）
$RootDir = Split-Path -Parent $PSScriptRoot
$c = Join-Path $RootDir 'cache'
if (-not (Test-Path $c)) {
    Write-Host '离线包尚未开始（cache\ 不存在）。请先运行 prefetch.cmd。' -ForegroundColor Yellow
    return
}
$files = Get-ChildItem $c -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'download.log' }
Write-Host '========== 已下载的离线包 ==========' -ForegroundColor Cyan
if ($files) {
    $files | Sort-Object FullName | ForEach-Object {
        Write-Host ('  {0,-34} {1,9} MB' -f $_.FullName.Substring($c.Length + 1), [math]::Round($_.Length / 1MB, 2))
    }
    Write-Host ('  合计: ' + [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1) + ' MB') -ForegroundColor Green
} else {
    Write-Host '  （暂无文件）'
}
$dl = Join-Path $c 'download.log'
if (Test-Path $dl) {
    Write-Host ''
    Write-Host '========== 最近下载进度（每 5% 一行）==========' -ForegroundColor Cyan
    Get-Content $dl -Tail 15 -Encoding UTF8
}
