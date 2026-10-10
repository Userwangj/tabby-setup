# ============================================================
#  uninstall.ps1 - Tabby 配置同步包 · 一键卸载
#  撤销 install.ps1 所做的一切。
#
#  程序卸载策略（重要）：
#    - Tabby            : 卸载（就是它本尊）
#    - PowerShell 7     : 【询问】若本机存在，让用户选择是否卸载
#                         （安装时会记录它是否本机原有，本包装的默认删）
#    - Node.js / npm    : 【保留】本机由 nvm 管理，非本包安装
#    - oh-my-posh       : 【询问】若本机存在，让用户选择是否卸载
#                         （安装时会记录它是否本机原有，本包装的默认删）
#
#  用法：
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Yes          # 不再询问
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -KeepApps     # 只还原设置，不卸载任何程序
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -UninstallOmp # 连 oh-my-posh 一起卸
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -KeepOmp      # 强制保留 oh-my-posh
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -UninstallPwsh# 连 PowerShell 7 一起卸
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -KeepPwsh     # 强制保留 PowerShell 7
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -KeepFont     # 保留字体
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -KeepConfig   # 保留 Tabby 配置
#    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -DryRun       # 只看计划，不动手
# ============================================================

param(
    [switch]$Yes,          # 不询问，直接执行
    [switch]$KeepApps,     # 只还原个性化设置，不卸载任何程序
    [switch]$UninstallOmp, # 一并卸载 oh-my-posh
    [switch]$KeepOmp,      # 强制保留 oh-my-posh
    [switch]$UninstallPwsh,# 一并卸载 PowerShell 7
    [switch]$KeepPwsh,     # 强制保留 PowerShell 7
    [switch]$KeepFont,     # 保留 JetBrainsMono Nerd Font
    [switch]$KeepConfig,   # 保留 Tabby config.yaml
    [switch]$DryRun        # 只打印计划，不做任何修改
)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'cache-lib.ps1')

$TabbyDir    = Join-Path $env:APPDATA 'tabby'
$ConfigPath  = Join-Path $TabbyDir 'config.yaml'
$PluginDir   = Join-Path $TabbyDir 'plugins'
$BinDir      = Join-Path $env:USERPROFILE 'bin'
$OmpPortable = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh'
$FontDir     = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$FontReg     = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$StateFile   = Join-Path $env:LOCALAPPDATA 'tabby-setup\install-state.json'
$ProfilePaths = @(
    (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
)
$BinFiles = @('tabbyhelp.cmd', 'tabbyhelp.txt', 'tabbycolors.cmd', 'show-theme.ps1',
              'tabbytheme.cmd', 'switch-theme.ps1', 'omp.cmd', 'omp-theme.ps1',
              'oh-my-posh.omp.json', 'oh-my-posh.theme.txt')

function Info($m)  { Write-Host $m -ForegroundColor Cyan }
function Ok($m)    { Write-Host $m -ForegroundColor Green }
function Warn($m)  { Write-Host $m -ForegroundColor Yellow }
function Step($m)  { Write-Host $m -ForegroundColor White }
function Get-Text([string]$p) { return (([System.IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)) -replace "^\uFEFF", '') }

function Stop-TabbySafe {
    Get-Process -Name Tabby -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $n = 0
    while ((Get-Process -Name Tabby -ErrorAction SilentlyContinue) -and $n -lt 40) { Start-Sleep -Milliseconds 250; $n++ }
    Start-Sleep -Milliseconds 700
}
function Find-Tabby {
    return @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Tabby\Tabby.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\tabby\Tabby.exe'),
        'C:\Program Files\Tabby\Tabby.exe',
        'C:\Program Files (x86)\Tabby\Tabby.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
function Remove-FromUserPath([string]$Entry) {
    $up = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $up) { return $false }
    $target = $Entry.TrimEnd('\')
    $parts = $up -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $target) }
    $new = ($parts -join ';')
    if ($new -ne $up) { [Environment]::SetEnvironmentVariable('Path', $new, 'User'); return $true }
    return $false
}

# ---- 读取 install 记录的状态（判断 oh-my-posh 是否本包安装）----
$state = $null
if (Test-Path $StateFile) { try { $state = (Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
$ompPreexisting = $null
if ($state -and ($state.PSObject.Properties.Name -contains 'ompPreexisting')) { $ompPreexisting = [bool]$state.ompPreexisting }
$ompInstalledByUs = $null
if ($state -and ($state.PSObject.Properties.Name -contains 'ompInstalledByUs')) { $ompInstalledByUs = [bool]$state.ompInstalledByUs }
elseif ($ompPreexisting -ne $null) { $ompInstalledByUs = (-not $ompPreexisting) }
$pwshPreexisting = $null
if ($state -and ($state.PSObject.Properties.Name -contains 'pwshPreexisting')) { $pwshPreexisting = [bool]$state.pwshPreexisting }
$pwshInstalledByUs = $null
if ($state -and ($state.PSObject.Properties.Name -contains 'pwshInstalledByUs')) { $pwshInstalledByUs = [bool]$state.pwshInstalledByUs }
elseif ($pwshPreexisting -ne $null) { $pwshInstalledByUs = (-not $pwshPreexisting) }
# 本机当前状态
$tabbyExe = Find-Tabby
$ompCmd   = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source
$pwshCmd  = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
$pwshAppx = Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue
$hasConfig = Test-Path $ConfigPath
$hasPlugins = (Test-Path (Join-Path $PluginDir 'node_modules')) -or
              (Test-Path (Join-Path $PluginDir 'package.json')) -or
              (Test-Path (Join-Path $PluginDir '.tabby-setup-npm.sig'))
$binPresent = @($BinFiles | Where-Object { Test-Path (Join-Path $BinDir $_) })
$ompPortablePresent = Test-Path $OmpPortable
$ompAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\oh-my-posh.exe'
# “存在”判定：PATH 命令 / winget 别名 / 便携目录 / Appx，任一命中即算存在
$ompPresent  = ([bool]$ompCmd) -or (Test-Path $ompAlias) -or $ompPortablePresent
$pwshPresent = ([bool]$pwshCmd) -or [bool]$pwshAppx
$cpPresent = Test-Path (Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\CompletionPredictor')
$fontNames = @()
try {
    $fp = Get-ItemProperty -Path $FontReg -ErrorAction SilentlyContinue
    $fontNames = @($fp.PSObject.Properties.Name | Where-Object { $_ -like 'JetBrainsMono Nerd Font Mono*' })
} catch { }
$profileHits = @()
foreach ($pp in $ProfilePaths) {
    if (Test-Path $pp) {
        $c = Get-Text $pp
        if (($c -match '# ==== oh-my-posh prompt') -or ($c -match '# ==== PSReadLine')) { $profileHits += $pp }
    }
}
$template = Get-Text (Join-Path $ScriptDir 'Microsoft.PowerShell_profile.ps1')

# ---- 决定 oh-my-posh 是否卸载（默认：本包装的删，原有/未知的留）----
$defaultRemoveOmp = ($ompInstalledByUs -eq $true)
$removeOmp = $false
if ($ompPresent -and -not $KeepApps) {
    if ($KeepOmp)          { $removeOmp = $false }
    elseif ($UninstallOmp) { $removeOmp = $true }
    elseif ($Yes -or $DryRun) { $removeOmp = $defaultRemoveOmp }
    else {
        $hint = if ($ompInstalledByUs -eq $true) { '本包安装/覆盖过' }
                elseif ($ompPreexisting -eq $true) { '安装前本机已存在，不是本包装的' }
                else { '来源未知（无安装记录）' }
        $def = if ($defaultRemoveOmp) { 'y' } else { 'n' }
        $ans = Read-Choice -Prompt "  检测到 oh-my-posh（$hint）。是否一并卸载？[y/n]" -Allowed @('y', 'n') -DefaultOnFail $def
        $removeOmp = ($ans -eq 'y')
    }
}

# ---- 决定 PowerShell 7 是否卸载（默认：本包装的删，原有/未知的留）----
$defaultRemovePwsh = ($pwshInstalledByUs -eq $true)
$removePwsh = $false
if ($pwshPresent -and -not $KeepApps) {
    if ($KeepPwsh)          { $removePwsh = $false }
    elseif ($UninstallPwsh) { $removePwsh = $true }
    elseif ($Yes -or $DryRun) { $removePwsh = $defaultRemovePwsh }
    else {
        $hint = if ($pwshInstalledByUs -eq $true) { '本包安装/覆盖过' }
                elseif ($pwshPreexisting -eq $true) { '安装前本机已存在，不是本包装的' }
                else { '来源未知（无安装记录）' }
        $def = if ($defaultRemovePwsh) { 'y' } else { 'n' }
        $ans = Read-Choice -Prompt "  检测到 PowerShell 7（$hint）。是否一并卸载？[y/n]" -Allowed @('y', 'n') -DefaultOnFail $def
        $removePwsh = ($ans -eq 'y')
    }
}

# ---- 打印计划 ----
Info '=================================================='
Info ' Tabby 配置同步包 · 卸载'
Info '=================================================='
Write-Host ''
Step '  将要移除的【个性化设置】：'
function PItem($ok, $label) { if ($ok) { Write-Host ("    [x] " + $label) } else { Write-Host ("    [ ] " + $label + "  (未发现，跳过)") -ForegroundColor DarkGray } }
PItem ($profileHits.Count -gt 0) ("PowerShell profile 中的 oh-my-posh / PSReadLine 块 (" + $profileHits.Count + " 个)")
PItem ($binPresent.Count -gt 0)  ("命令: tabbyhelp / tabbycolors / tabbytheme / omp (" + $binPresent.Count + " 个文件)")
PItem $ompPortablePresent        '便携版 oh-my-posh (%LOCALAPPDATA%\Programs\oh-my-posh)'
PItem $cpPresent                 'PowerShell 模块 CompletionPredictor'
PItem ($fontNames.Count -gt 0)   ("字体 JetBrainsMono Nerd Font Mono (" + $fontNames.Count + " 个样式)")
PItem $hasPlugins                'Tabby npm 插件 (node_modules / package.json)'
PItem ($hasConfig -and -not $KeepConfig) 'Tabby 配置 config.yaml（先备份再复原为默认）'
Write-Host ''
if (-not $KeepApps) {
    Warn '  将要卸载的【程序】：'
    if ($tabbyExe) { Write-Host "    [x] Tabby 终端  ($tabbyExe)" } else { Write-Host '    [ ] Tabby（未发现）' -ForegroundColor DarkGray }
    if ($ompPresent) {
        if ($removeOmp) {
            $op = if ($ompPortablePresent) { $OmpPortable } elseif ($ompCmd) { $ompCmd } else { $ompAlias }
            Write-Host "    [x] oh-my-posh  ($op)"
        }
        else { Write-Host "    [ ] oh-my-posh  -> 保留" -ForegroundColor DarkGray }
    } else { Write-Host '    [ ] oh-my-posh（未发现）' -ForegroundColor DarkGray }
    if ($pwshPresent) {
        if ($removePwsh) { Write-Host "    [x] PowerShell 7  ($pwshCmd)" }
        else             { Write-Host "    [ ] PowerShell 7  -> 保留（$pwshCmd）" -ForegroundColor DarkGray }
    } else { Write-Host '    [ ] PowerShell 7（未发现）' -ForegroundColor DarkGray }
    Write-Host ''
    Step '  保留（不卸载）：'
    Write-Host '    [ ] Node.js / npm  （nvm4w 管理，非本包安装）'
} else {
    Step '  -KeepApps：仅还原个性化设置，不卸载任何程序。'
}
Write-Host ''

if ($DryRun) { Warn '  -DryRun：只显示计划，未做任何修改。'; exit 0 }

if (-not $Yes) {
    $ans = Read-Choice -Prompt '  确认执行卸载？[y=继续 / n=取消]' -Allowed @('y', 'n') -DefaultOnFail 'n'
    if ($ans -ne 'y') { Warn '  已取消，未做任何修改。'; exit 0 }
}

$removed = 0

# ---- 1. 关闭 Tabby ----
Step '[1/9] 关闭 Tabby...'
Invoke-WithSpinner '正在关闭 Tabby...' 'Tabby 已关闭' { Stop-TabbySafe }

# ---- 2. PowerShell profile 中的 oh-my-posh / PSReadLine 块 ----
Step '[2/9] 清理 PowerShell profile...'
foreach ($pp in $ProfilePaths) {
    if (-not (Test-Path $pp)) { continue }
    $cur = Get-Text $pp
    if ($cur.Trim() -eq $template.Trim()) {
        Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue
        Ok "       删除整个 profile（内容即本包模板）: $pp"
        $removed++
    } elseif (($cur -match '# ==== oh-my-posh prompt') -or ($cur -match '# ==== PSReadLine')) {
        # 分别剥离本包的 omp 块与 PSReadLine 块（支持只写了其中一块的情况）
        $new = [regex]::Replace($cur, '(?s)\r?\n?# ==== oh-my-posh prompt.*?# ==== end oh-my-posh ====\s*', "`r`n")
        $new = [regex]::Replace($new, '(?s)\r?\n?# ==== PSReadLine.*?# ==== end PSReadLine ====\s*', "`r`n")
        $new = $new.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($new)) {
            Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue
            Ok "       删除 profile: $pp"
        } else {
            [System.IO.File]::WriteAllText($pp, ($new + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
            Ok "       移除本包块（保留你原有内容）: $pp"
        }
        $removed++
    }
}
if ($removed -eq 0) { Warn '       未发现本包写入的 profile 块' }

# ---- 3. bin 命令 ----
Step '[3/9] 删除 tabbyhelp / tabbycolors / tabbytheme / omp 命令...'
$n = 0
foreach ($f in $BinFiles) {
    $p = Join-Path $BinDir $f
    if (Test-Path $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; $n++ }
}
Ok "       已删除 $n 个命令文件"
if ((Test-Path $BinDir) -and -not (Get-ChildItem $BinDir -Force -ErrorAction SilentlyContinue)) {
    Remove-Item $BinDir -Force -ErrorAction SilentlyContinue
    if (Remove-FromUserPath $BinDir) { Ok '       bin 目录已空，并已从 PATH 移除' }
} else {
    Warn '       bin 目录仍有其它文件，保留目录（未从 PATH 移除）'
}

# ---- 4. 便携版 oh-my-posh ----
Step '[4/9] 便携版 oh-my-posh...'
if ($ompPortablePresent) {
    Invoke-WithSpinner '正在删除便携版 oh-my-posh...' '便携版 oh-my-posh 已删除' {
        Remove-Item $OmpPortable -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Remove-FromUserPath $OmpPortable) { Ok '       已从 PATH 移除 oh-my-posh 便携目录' }
} else {
    Warn '       未发现便携版目录，跳过'
}

# ---- 5. CompletionPredictor ----
Step '[5/9] 移除 CompletionPredictor 模块...'
if ($cpPresent) {
    Remove-Item (Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\CompletionPredictor') -Recurse -Force -ErrorAction SilentlyContinue
    Ok '       已删除 CompletionPredictor'
} else { Warn '       未发现，跳过' }

# ---- 6. 字体 ----
Step '[6/9] 移除 JetBrainsMono Nerd Font...'
if ($KeepFont) { Warn '       -KeepFont：保留字体' }
elseif ($fontNames.Count -gt 0) {
    foreach ($name in $fontNames) {
        try {
            $val = (Get-ItemProperty -Path $FontReg -Name $name -ErrorAction SilentlyContinue).$name
            if ($val -and (Test-Path $val)) { Remove-Item -LiteralPath $val -Force -ErrorAction SilentlyContinue }
            Remove-ItemProperty -Path $FontReg -Name $name -Force -ErrorAction SilentlyContinue
        } catch { }
    }
    Get-ChildItem $FontDir -Filter 'JetBrainsMonoNerdFontMono-*.ttf' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Ok "       已删除 $($fontNames.Count) 个字体样式 + 文件"
} else { Warn '       未发现，跳过' }

# ---- 7. Tabby npm 插件 ----
Step '[7/9] 移除 Tabby npm 插件...'
$n = 0
foreach ($x in @('node_modules', 'package.json', 'package-lock.json', '.tabby-setup-npm.sig')) {
    $p = Join-Path $PluginDir $x
    if (Test-Path $p) {
        if ($x -eq 'node_modules') { Invoke-WithSpinner '正在删除 npm 插件...' 'npm 插件已删除' { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue } }
        else { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        $n++
    }
}
if ($n -gt 0) { Ok "       已移除 $n 项" } else { Warn '       未发现，跳过' }

# ---- 8. Tabby 配置 ----
Step '[8/9] 还原 Tabby 配置...'
if ($KeepConfig) { Warn '       -KeepConfig：保留 config.yaml' }
elseif ($hasConfig) {
    $bak = Join-Path $TabbyDir 'config.yaml.uninstalled-bak'
    Copy-Item $ConfigPath $bak -Force -ErrorAction SilentlyContinue
    Remove-Item $ConfigPath -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $TabbyDir 'config.yaml.backup') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $TabbyDir 'config.yaml.tmp') -Force -ErrorAction SilentlyContinue
    Ok "       已移除 config.yaml（备份: $bak），Tabby 下次启动将生成默认配置"
} else { Warn '       未发现 config.yaml，跳过' }

# ---- 9. 卸载程序：仅 Tabby（oh-my-posh 按选择）----
Step '[9/9] 卸载程序...'
if ($KeepApps) {
    Warn '       -KeepApps：跳过程序卸载'
} else {
    $winget = Get-Command winget -ErrorAction SilentlyContinue

    # Tabby（优先用它自带的 Squirrel 卸载器）
    $te = Find-Tabby
    if ($te) {
        $updateExe = Join-Path (Split-Path $te -Parent) 'Update.exe'
        if (Test-Path $updateExe) {
            Invoke-WithSpinner '正在卸载 Tabby...' 'Tabby 已卸载' { & $updateExe --uninstall *> $null }
        } elseif ($winget) {
            Invoke-WithSpinner '正在卸载 Tabby...' 'Tabby 已卸载' { & winget uninstall --id Eugeny.Tabby --silent --accept-source-agreements *> $null }
        } else {
            Warn '       未找到 Tabby 卸载器，请手动在“设置→应用”卸载'
        }
        if (Find-Tabby) { Warn '       Tabby 可能未完全卸载，可手动在“设置→应用”处理' }
    } else { Warn '       未发现 Tabby，跳过' }

    # oh-my-posh（用户选择；便携版已在步骤 4 删除）
    if ($removeOmp) {
        if (Test-Path $ompAlias) {
            $done = $false
            if ($winget) {
                Invoke-WithSpinner '正在卸载 oh-my-posh...' 'oh-my-posh 已卸载' {
                    & winget uninstall --id JanDeDobbeleer.OhMyPosh --silent --accept-source-agreements *> $null
                }
                if (-not (Test-Path $ompAlias)) { $done = $true }
            }
            if (-not $done) { Warn '       oh-my-posh 未能自动卸载，可手动: winget uninstall JanDeDobbeleer.OhMyPosh' }
        } elseif ($ompPortablePresent) {
            Ok '       便携版 oh-my-posh 已在步骤 4 删除'
        } else {
            Warn '       未找到可自动卸载的 oh-my-posh（可能已移除）'
        }
    } elseif ($ompPresent) {
        Ok '       按选择保留 oh-my-posh'
    }

    # PowerShell 7（用户选择）
    if ($removePwsh) {
        $pa = Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue
        if ($pa) {
            Invoke-WithSpinner '正在卸载 PowerShell 7...' 'PowerShell 7 已卸载' {
                $pa | Remove-AppxPackage -ErrorAction SilentlyContinue
            }
            if (Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue) {
                Warn '       PowerShell 7 未能卸载（可能被占用），可手动在“设置→应用”卸载'
            } else {
                # Tabby 默认 shell 回退到系统自带 Windows PowerShell 5.1
                if (Test-Path $ConfigPath) {
                    $ct = [System.IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8)
                    if ($ct -match 'local:powershell-core') {
                        $ct = $ct -replace 'local:powershell-core', 'local:powershell'
                        [System.IO.File]::WriteAllText($ConfigPath, $ct, (New-Object System.Text.UTF8Encoding($false)))
                        Ok '       Tabby 默认 shell 已回退为 Windows PowerShell 5.1 (local:powershell)'
                    }
                }
            }
        } else { Warn '       未发现 PowerShell 7 (Appx)，跳过' }
    } elseif ($pwshPresent) {
        Ok '       按选择保留 PowerShell 7'
    }

    Write-Host ''
    Warn '  已保留 Node.js / npm（nvm4w 管理，非本包安装）。'
}

# 清理安装状态记录
Remove-Item $StateFile -Force -ErrorAction SilentlyContinue

Write-Host ''
Ok '=================================================='
Ok ' 卸载完成。'
Ok '=================================================='
Warn '  提示：环境变量 PATH 的变更需新开终端窗口才生效。'
