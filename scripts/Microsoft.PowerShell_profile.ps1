# ==== oh-my-posh prompt (installed by tabby-setup) ====
# 主题文件随同步包部署在 %USERPROFILE%\bin\oh-my-posh.omp.json
# 想换主题：运行 omp 命令，或把任意 .omp.json 覆盖到该路径
# --- Git 加速：优先用 Git for Windows 原生 git（仅当前会话，不改系统变量）---
# cmd\git.exe 是定位用的包装器，每次调用会多起一个进程（本机实测 ~58ms，原生 ~36ms）。
# 把同级的 mingw64\bin 插到 Git\cmd 之前；System32 仍在最前，不影响 curl 等系统命令。
# 想关闭：设环境变量 TABBY_SETUP_GIT_FAST=0 再新开标签页。
if ($env:TABBY_SETUP_GIT_FAST -ne '0') {
    & {
        $parts = $env:Path -split ';'
        $at = -1; $fast = $null
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $p = $parts[$i].TrimEnd('\')
            if ($p -match '(?i)\\Git\\cmd$') {
                $cand = Join-Path (Split-Path $p -Parent) 'mingw64\bin'
                if (Test-Path (Join-Path $cand 'git.exe')) { $fast = $cand; $at = $i; break }
            }
        }
        if ($fast -and ($parts -notcontains $fast)) {
            $before = if ($at -gt 0) { $parts[0..($at - 1)] } else { @() }
            $after = $parts[$at..($parts.Count - 1)]
            $env:Path = (($before + $fast + $after) -join ';')
        }
    }
}
# --- oh-my-posh 提示符 ---
$ompTheme = Join-Path $env:USERPROFILE 'bin\oh-my-posh.omp.json'
$ompExe = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source
if (-not $ompExe) { $ompExe = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\oh-my-posh.exe' }
if (-not (Test-Path $ompExe)) { $ompExe = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\oh-my-posh.exe' }
if ((Test-Path $ompTheme) -and (Test-Path $ompExe)) {
    & $ompExe init pwsh --config $ompTheme | Invoke-Expression
    # 异步提示符（oh-my-posh 31+，仅 pwsh 6+）：由常驻 oh-my-posh serve 后台渲染，
    # 不再为每条命令新起进程，减少「命令后立刻打字」的延迟感。
    # 想退回同步渲染：设环境变量 POSH_DISABLE_STREAMING=1 再新开标签页。
    if ($PSVersionTable.PSEdition -eq 'Core' -and
        $PSVersionTable.PSVersion.Major -ge 6 -and
        (Get-Command Enable-PoshStreaming -ErrorAction SilentlyContinue)) {
        try { Enable-PoshStreaming } catch { }
        # oh-my-posh 31.x 的 init 脚本只定义 Enable-KeyHandlers 却不调用它。缺了它，回车
        # 不会把流式渲染状态重置为 NEW，提示符会一直停留在首次渲染（路径与 git 分支
        # 不再刷新，看起来就像 git 段消失了）。这里显式补上。
        try { Enable-KeyHandlers } catch { }
    }
}
# ==== end oh-my-posh ====

# ==== PSReadLine 预测性智能提示（灰字内联补全，类似 fish / Clink）====
# 需要 PSReadLine >= 2.1；Windows PowerShell 5.1 自带 2.0，install.ps1 会尝试升级
# 默认只用「历史」预测（内存内、极快）。CompletionPredictor 插件预测会在每次按键时
# 实时计算命令补全，打字 / 敲空格时可能明显卡顿，所以改为按需开启：
#   设环境变量 TABBY_SETUP_PLUGIN_PREDICTION=1（新开标签页生效）即可启用插件预测
try {
    Import-Module PSReadLine -ErrorAction Stop
    $predSource = 'History'
    if ($env:TABBY_SETUP_PLUGIN_PREDICTION -eq '1') {
        Import-Module CompletionPredictor -ErrorAction SilentlyContinue
        if (Get-Module CompletionPredictor) { $predSource = 'HistoryAndPlugin' }
    }
    Set-PSReadLineOption -PredictionSource $predSource -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
} catch { }
# ==== end PSReadLine ====
