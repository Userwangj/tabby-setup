# ==== oh-my-posh prompt (installed by tabby-setup) ====
# 主题文件随同步包部署在 %USERPROFILE%\bin\oh-my-posh.omp.json
# 想换主题：运行 omp 命令，或把任意 .omp.json 覆盖到该路径
$ompTheme = Join-Path $env:USERPROFILE 'bin\oh-my-posh.omp.json'
$ompExe = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source
if (-not $ompExe) { $ompExe = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\oh-my-posh.exe' }
if (-not (Test-Path $ompExe)) { $ompExe = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\oh-my-posh.exe' }
if ((Test-Path $ompTheme) -and (Test-Path $ompExe)) {
    & $ompExe init pwsh --config $ompTheme | Invoke-Expression
}
# ==== end oh-my-posh ====

# ==== PSReadLine 预测性智能提示（灰字内联补全，类似 fish / Clink）====
# 需要 PSReadLine >= 2.1；Windows PowerShell 5.1 自带 2.0，install.ps1 会尝试升级
try {
    Import-Module PSReadLine -ErrorAction Stop
    Import-Module CompletionPredictor -ErrorAction SilentlyContinue   # 命令名级预测 (pwsh)
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
} catch { }
# ==== end PSReadLine ====
