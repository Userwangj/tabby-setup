# ============================================================
#  cache-lib.ps1 - 离线包共享库
#  由 install.ps1 与 prefetch.ps1 共同 dot-source
#  提供：带进度条下载 / manifest 读写 / 版本比较 / 上游版本探测 /
#        文件型组件的来源决策 / 版本检查交互
# ============================================================

# ---- 实时显示工具（单行刷新 + 进度条/跑马灯，任何控制台/Tabby 都可见）----
function Format-Speed([double]$bps) {
    if ($bps -ge 1MB) { return ('{0:N1} MB/s' -f ($bps / 1MB)) }
    if ($bps -ge 1KB) { return ('{0:N0} KB/s' -f ($bps / 1KB)) }
    return ('{0:N0} B/s' -f $bps)
}
# 计算字符串的“显示宽度”（中文/全角算 2 列，块字符算 1 列）
function Get-DisplayWidth([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return 0 }
    $w = 0
    foreach ($ch in $s.ToCharArray()) {
        $c = [int][char]$ch
        if (($c -ge 0x1100 -and $c -le 0x115F) -or
            ($c -ge 0x2E80 -and $c -le 0x303E) -or
            ($c -ge 0x3041 -and $c -le 0x33FF) -or
            ($c -ge 0x3400 -and $c -le 0x4DBF) -or
            ($c -ge 0x4E00 -and $c -le 0x9FFF) -or
            ($c -ge 0xA000 -and $c -le 0xA4CF) -or
            ($c -ge 0xAC00 -and $c -le 0xD7A3) -or
            ($c -ge 0xF900 -and $c -le 0xFAFF) -or
            ($c -ge 0xFE30 -and $c -le 0xFE4F) -or
            ($c -ge 0xFF00 -and $c -le 0xFF60) -or
            ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { $w += 2 } else { $w += 1 }
    }
    return $w
}
function Get-ConWidth {
    try { $w = [Console]::WindowWidth; if ($w -ge 40) { return $w } } catch { }
    return 80
}
function Write-LiveProgress([string]$Text) {
    try {
        $cw = Get-ConWidth
        $pad = $cw - 1 - (Get-DisplayWidth $Text)
        if ($pad -lt 0) { $pad = 0 }
        [Console]::Write("`r" + $Text + (' ' * $pad))
    } catch { }
}
function Complete-LiveProgress([string]$Text) {
    try {
        Write-LiveProgress $Text
        [Console]::Write("`n")
    } catch { }
}
# 进度条填充字符：按“当前控制台输出编码”逐个选择可渲染的字符。
# 例如 GBK 含 █(U+2588) 不含 ░(U+2591)，则用 █ 配 - ，避免出现 ? 。
function Test-CharRenderable([char]$ch) {
    try {
        $enc = [Console]::OutputEncoding
        $b = $enc.GetBytes([string]$ch)
        # 无法映射的字符会被编码成单个 '?' (0x3F)
        if ($b.Length -eq 1 -and $b[0] -eq 0x3F) { return $false }
        return $true
    } catch { return $false }
}
$BarFullChar = [char]0x2588    # █
$BarEmptyChar = [char]0x2591   # ░
try {
    if ([Console]::IsOutputRedirected) {
        # 重定向到日志/管道时用纯 ASCII，保证日志可读
        $BarFullChar = '#'; $BarEmptyChar = '-'
    } else {
        if (-not (Test-CharRenderable $BarFullChar)) { $BarFullChar = '#' }
        if (-not (Test-CharRenderable $BarEmptyChar)) { $BarEmptyChar = '-' }
    }
} catch { }

# 生成带填充块的进度条行（宽度自适应控制台）
function New-ProgressLine {
    param([string]$Activity, [int]$Pct, [string]$MbText, [string]$Spd, [string]$Eta = '')
    $cw = Get-ConWidth
    $act = $Activity
    while ((Get-DisplayWidth $act) -gt 16 -and $act.Length -gt 0) { $act = $act.Substring(0, $act.Length - 1) }
    $head = "   $act  ["
    $tail = "]  $Pct%   $MbText"
    if ($Spd) { $tail += "   $Spd" }
    $fixed = (Get-DisplayWidth $head) + (Get-DisplayWidth $tail)
    if ($Eta) { $fixed += (Get-DisplayWidth ("   $Eta")) }
    $barW = $cw - 1 - $fixed
    if ($barW -lt 8) { $barW = 8 }
    if ($barW -gt 40) { $barW = 40 }
    $filled = [int][Math]::Floor($Pct / 100.0 * $barW)
    if ($filled -gt $barW) { $filled = $barW }
    if ($filled -lt 0) { $filled = 0 }
    $full = [string]$BarFullChar
    $empty = [string]$BarEmptyChar
    $bar = ($full * $filled) + ($empty * ($barW - $filled))
    $line = $head + $bar + $tail
    if ($Eta) { $line += "   $Eta" }
    return $line
}
# 生成确定性进度条行（本地解压/复制用，Detail 如 "12/98 项"）
function Write-DeterminateProgress {
    param([string]$Activity, [int]$Pct, [string]$Detail, [string]$Eta = '')
    Write-LiveProgress (New-ProgressLine -Activity $Activity -Pct $Pct -MbText $Detail -Spd '' -Eta $Eta)
}
# 在独立 runspace 中跑“跑马灯”进度条，主线程照常阻塞执行安装
function Start-Spinner([string]$Message) {
    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            param($msg, $full, $empty)
            $seg = 6; $barW = 24; $pos = 0; $dir = 1
            try {
                while ($true) {
                    $sw = 80
                    try { $w0 = [Console]::WindowWidth; if ($w0 -ge 40) { $sw = $w0 } } catch { }
                    $padN = $barW - $seg - $pos; if ($padN -lt 0) { $padN = 0 }
                    $bar = ($empty * $pos) + ($full * $seg) + ($empty * $padN)
                    $line = "   $msg  [$bar]"
                    $disp = ($line -replace '[\u1100-\u115F\u2E80-\u9FFF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6]', 'xx')
                    $pad = $sw - 1 - $disp.Length
                    if ($pad -lt 0) { $pad = 0 }
                    [Console]::Write("`r" + $line + (' ' * $pad))
                    $pos += $dir
                    if ($pos -ge ($barW - $seg)) { $pos = $barW - $seg; $dir = -1 }
                    elseif ($pos -le 0) { $pos = 0; $dir = 1 }
                    Start-Sleep -Milliseconds 90
                }
            } catch { }
        }).AddArgument($Message).AddArgument([string]$BarFullChar).AddArgument([string]$BarEmptyChar)
        $h = $ps.BeginInvoke()
        return [pscustomobject]@{ PS = $ps; RS = $rs; Handle = $h }
    } catch { return $null }
}
function Stop-Spinner($Spinner, [string]$DoneMessage = '') {
    if (-not $Spinner) { return }
    try { $Spinner.PS.Stop() } catch { }
    try { $Spinner.PS.Dispose() } catch { }
    try { $Spinner.RS.Close(); $Spinner.RS.Dispose() } catch { }
    if ($DoneMessage) { Complete-LiveProgress ("   " + $DoneMessage) }
}
function Invoke-WithSpinner {
    param([string]$Message, [string]$DoneMessage, [scriptblock]$Action)
    $sp = Start-Spinner $Message
    try { & $Action } finally { Stop-Spinner $sp $DoneMessage }
}

# ---- 本地解压（带确定性进度条）----
function Expand-ZipWithProgress {
    param([string]$ZipPath, [string]$Destination, [string]$Activity = '解压', [switch]$NoClear)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    if (-not (Test-Path $ZipPath)) {
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "       压缩包不存在，跳过解压：$ZipPath" }
        return $false
    }
    if (-not (Test-ZipFile $ZipPath)) {
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "       压缩包无效或不完整，跳过解压：$ZipPath" }
        return $false
    }
    if (-not $NoClear -and (Test-Path $Destination)) { Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $entries = @($zip.Entries)
        $total = $entries.Count
        if ($total -eq 0) { return $true }
        $i = 0
        foreach ($e in $entries) {
            $i++
            $target = Join-Path $Destination ($e.FullName -replace '/', '\')
            if ([string]::IsNullOrEmpty($e.Name)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            } else {
                $dir = Split-Path -Parent $target
                if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
            }
            if (($i % 10) -eq 0 -or $i -eq $total) {
                Write-DeterminateProgress -Activity $Activity -Pct ([int]($i * 100 / $total)) -Detail "$i/$total 项"
            }
        }
        Complete-LiveProgress (New-ProgressLine -Activity $Activity -Pct 100 -MbText "$total/$total 项" -Spd '')
        return $true
    } catch {
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "       解压失败：$($_.Exception.Message)" }
        return $false
    } finally {
        if ($zip) { try { $zip.Dispose() } catch { } }
    }
}

# ---- 打包目录为 zip（标准 zip，.NET 与 tar.exe 均可读写）----
function Compress-TreeToZip {
    param([string]$Source, [string]$ZipPath, [string]$Activity = '打包')
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $srcFull = (Resolve-Path -LiteralPath $Source -ErrorAction SilentlyContinue).Path
    if (-not $srcFull) { return }
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue }
    $dir = [System.IO.Path]::GetDirectoryName($ZipPath)
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $sp = Start-Spinner "正在$Activity ..."
    try {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($srcFull, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    } finally { Stop-Spinner $sp "$Activity 完成" }
}

# ---- 快速解压（优先 tar.exe，带确定性进度条；无 tar 时退回逐项解压）----
function Expand-ZipFast {
    param([string]$ZipPath, [string]$Destination, [string]$Activity = '解压', [switch]$NoClear)
    if (-not $NoClear -and (Test-Path $Destination)) { Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tar) { Expand-ZipWithProgress -ZipPath $ZipPath -Destination $Destination -Activity $Activity -NoClear; return }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $total = 0
    try {
        $z = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        foreach ($e in $z.Entries) { if (-not [string]::IsNullOrEmpty($e.Name)) { $total++ } }
        $z.Dispose()
    } catch { }
    $argStr = '-xf "{0}" -C "{1}"' -f $ZipPath, $Destination
    $proc = Start-Process -FilePath $tar.Source -ArgumentList $argStr -PassThru -WindowStyle Hidden
    $last = -1
    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 700
        if ($proc.HasExited) { break }
        $done = 0
        try { foreach ($null in [System.IO.Directory]::EnumerateFiles($Destination, '*', [System.IO.SearchOption]::AllDirectories)) { $done++ } } catch { }
        if ($total -gt 0 -and $done -gt $total) { $done = $total }
        $pct = 0; if ($total -gt 0) { $pct = [int]($done * 100 / $total) }
        if ($pct -ne $last) { Write-DeterminateProgress -Activity $Activity -Pct $pct -Detail "$done/$total 项"; $last = $pct }
    }
    $proc.WaitForExit()
    Complete-LiveProgress (New-ProgressLine -Activity $Activity -Pct 100 -MbText "$total/$total 项" -Spd '')
    if ($proc.ExitCode -ne 0) { throw "tar 解压失败（exit=$($proc.ExitCode)）：$ZipPath" }
}

# ---- 本地目录复制（带确定性进度条，按文件数）----
# 优先用 robocopy（原生多线程，比 PowerShell 逐文件快 5~7 倍），
# 主线程轮询目标文件数来刷新进度；没有 robocopy 时退化为 .NET 逐文件复制。
function Copy-TreeWithProgress {
    param([string]$Source, [string]$Destination, [string]$Activity = '复制')

    $srcFull = (Resolve-Path -LiteralPath $Source -ErrorAction SilentlyContinue).Path
    if (-not $srcFull) { return }
    $total = 0
    try {
        foreach ($null in [System.IO.Directory]::EnumerateFiles($srcFull, '*', [System.IO.SearchOption]::AllDirectories)) { $total++ }
    } catch { }
    if ($total -eq 0) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    # 统计目标现有文件数（快速，不产生对象）
    $countDst = {
        $n = 0
        try { foreach ($null in [System.IO.Directory]::EnumerateFiles($Destination, '*', [System.IO.SearchOption]::AllDirectories)) { $n++ } } catch { }
        return $n
    }

    $rc = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($rc) {
        # robocopy：/E 含空目录 /MT 多线程 /NFL /NDL 不刷屏 /R:1 /W:1 少重试
        $argStr = '"{0}" "{1}" /E /MT:16 /NFL /NDL /NJH /NJS /NP /R:1 /W:1' -f $srcFull, $Destination
        $proc = Start-Process -FilePath $rc.Source -ArgumentList $argStr -PassThru -WindowStyle Hidden
        $lastPct = -1
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 800
            if ($proc.HasExited) { break }
            $done = & $countDst
            if ($done -gt $total) { $done = $total }
            $pct = [int]($done * 100 / $total)
            if ($pct -ne $lastPct) {
                Write-DeterminateProgress -Activity $Activity -Pct $pct -Detail "$done/$total 文件"
                $lastPct = $pct
            }
        }
        $proc.WaitForExit()
        $code = $proc.ExitCode
        Complete-LiveProgress (New-ProgressLine -Activity $Activity -Pct 100 -MbText "$total/$total 文件" -Spd '')
        if ($code -ge 8) { throw "robocopy 复制失败（exit=$code）：$Source -> $Destination" }
        return
    }

    # 退化方案：.NET 逐文件复制（仍比 cmdlet 循环快）
    $srcLen = $srcFull.Length
    $i = 0
    foreach ($f in [System.IO.Directory]::EnumerateFiles($srcFull, '*', [System.IO.SearchOption]::AllDirectories)) {
        $i++
        $rel = $f.Substring($srcLen).TrimStart('\')
        $target = Join-Path $Destination $rel
        $dir = [System.IO.Path]::GetDirectoryName($target)
        if ($dir -and -not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
        try { [System.IO.File]::Copy($f, $target, $true) } catch { }
        if (($i % 50) -eq 0 -or $i -eq $total) {
            Write-DeterminateProgress -Activity $Activity -Pct ([int]($i * 100 / $total)) -Detail "$i/$total 文件"
        }
    }
    Complete-LiveProgress (New-ProgressLine -Activity $Activity -Pct 100 -MbText "$total/$total 文件" -Spd '')
}

# ---- 流式下载 + 实时进度条 ----
function Get-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutFile,
        [long]$MinBytes = 0,
        [int]$TimeoutSec = 900,
        [string]$Activity = 'Downloading',
        [long]$ExpectedBytes = 0,
        [string]$LogFile = ''
    )
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $resp = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $req = [System.Net.HttpWebRequest]::Create($Url)
                $req.UserAgent = 'tabby-setup'
                $req.Timeout = $TimeoutSec * 1000
                $req.ReadWriteTimeout = $TimeoutSec * 1000
                $req.AllowAutoRedirect = $true
                try { $req.ServicePoint.Expect100Continue = $false } catch { }
                $resp = $req.GetResponse()
                break
            } catch {
                if ($attempt -ge 3) { throw }
                Start-Sleep -Seconds (2 * $attempt)
            }
        }
        $total = $resp.ContentLength
        if ($total -le 0 -and $ExpectedBytes -gt 0) { $total = $ExpectedBytes }
        $in = $resp.GetResponseStream()
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
        $out = [System.IO.File]::Create($OutFile)
        $lastLog = [datetime]::MinValue
        $lastPct = -100
        if ($LogFile) { Add-Content -Path $LogFile -Value ("$((Get-Date).ToString('HH:mm:ss'))  START  $Activity  <- $Url") -Encoding UTF8 -ErrorAction SilentlyContinue }
        try {
            $buffer = New-Object byte[] 131072
            $sum = 0
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while (($read = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $out.Write($buffer, 0, $read)
                $sum += $read
                $recvMb = [math]::Round($sum / 1MB, 1)
                $spdVal = if ($sw.Elapsed.TotalSeconds -gt 0) { $sum / $sw.Elapsed.TotalSeconds } else { 0 }
                $spd = Format-Speed $spdVal
                if ($total -gt 0) {
                    $pct = [int](($sum / $total) * 100)
                    if ($pct -gt 100) { $pct = 100 }
                    $status = "$recvMb/$([math]::Round($total / 1MB, 1)) MB"
                    $eta = ''
                    if ($spdVal -gt 1024) {
                        $remain = ($total - $sum) / $spdVal
                        if ($remain -ge 0 -and $remain -lt 86400) { $eta = 'ETA ' + ([TimeSpan]::FromSeconds([int]$remain)).ToString('mm\:ss') }
                    }
                    Write-LiveProgress (New-ProgressLine -Activity $Activity -Pct $pct -MbText $status -Spd $spd -Eta $eta)
                } else {
                    $pct = -1
                    $status = "$recvMb MB"
                    Write-LiveProgress ("   $Activity   $status   $spd")
                }
                if ($LogFile) {
                    $now = Get-Date
                    if (($pct -ge 0 -and ($pct - $lastPct) -ge 5) -or (($now - $lastLog).TotalSeconds -ge 5)) {
                        Add-Content -Path $LogFile -Value ("$($now.ToString('HH:mm:ss'))  $Activity  $status  ($pct%)  $spd") -Encoding UTF8 -ErrorAction SilentlyContinue
                        $lastPct = $pct; $lastLog = $now
                    }
                }
            }
        } finally {
            $out.Close(); $in.Close(); $resp.Close()
        }
        Complete-LiveProgress ("   $Activity   完成   $([math]::Round($sum / 1MB, 1)) MB")
        if ($LogFile -and (Test-Path $OutFile)) {
            Add-Content -Path $LogFile -Value ("$((Get-Date).ToString('HH:mm:ss'))  DONE   $Activity  $([math]::Round((Get-Item $OutFile).Length / 1MB, 1)) MB") -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $OutFile)) { return $false }
        $len = (Get-Item $OutFile).Length
        if ($total -gt 0 -and $len -ne $total) {
            if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "       Incomplete download ($([math]::Round($len/1MB,1)) / $([math]::Round($total/1MB,1)) MB)" }
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        if ($ExpectedBytes -gt 0 -and $len -ne $ExpectedBytes) {
            if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "       Size mismatch (got $len, expected $ExpectedBytes bytes)" }
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        if ($MinBytes -gt 0 -and $len -lt $MinBytes) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue; return $false }
        return $true
    } catch {
        try { Complete-LiveProgress "   $Activity   失败" } catch { }
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "       Download error: $($_.Exception.Message)" }
        # 最后兜底：curl（静默），应对个别 URL 的 TLS/代理握手问题
        try {
            curl.exe -L -s -m $TimeoutSec --retry 3 --retry-delay 2 -o $OutFile $Url
            if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0) -and ($MinBytes -le 0 -or (Get-Item $OutFile).Length -ge $MinBytes)) { return $true }
        } catch { }
        # 失败：清理可能残留的不完整文件，避免下次被误当有效包使用
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# ---- manifest ----
function Get-CacheManifest {
    param([string]$CacheDir)
    $mp = Join-Path $CacheDir 'manifest.json'
    if (Test-Path $mp) { try { return (Get-Content $mp -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
    return $null
}
function Save-CacheManifest {
    param([string]$CacheDir, $Manifest)
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    ($Manifest | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $CacheDir 'manifest.json') -Encoding UTF8
}
function Set-ManifestEntry {
    param([string]$CacheDir, [string]$Key, [string]$Version, [string]$File)
    $m = Get-CacheManifest $CacheDir
    if (-not $m) { $m = New-Object psobject }
    $entry = [pscustomobject]@{ version = $Version; file = $File; savedAt = (Get-Date).ToString('s') }
    if ($m.PSObject.Properties.Name -contains $Key) { $m.$Key = $entry }
    else { $m | Add-Member -NotePropertyName $Key -NotePropertyValue $entry -Force }
    if ($m.PSObject.Properties.Name -contains 'preparedAt') { $m.preparedAt = (Get-Date).ToString('s') }
    else { $m | Add-Member -NotePropertyName preparedAt -NotePropertyValue (Get-Date).ToString('s') -Force }
    Save-CacheManifest $CacheDir $m
}

# ---- 缓存文件路径 ----
function Get-CachePath {
    param([string]$CacheDir, [string]$Key)
    switch ($Key) {
        'tabby' { return (Join-Path $CacheDir 'tabby-setup.exe') }
        'font'  { return (Join-Path $CacheDir 'JetBrainsMono.zip') }
        'node'  { return (Join-Path $CacheDir 'node-win-x64.zip') }
        'pwsh'  { return (Join-Path $CacheDir 'PowerShell.msixbundle') }
        'omp'   { return (Join-Path $CacheDir 'oh-my-posh.exe') }
        'ompthemes' { return (Join-Path $CacheDir 'oh-my-posh-themes.zip') }
        default { return (Join-Path $CacheDir "$Key.bin") }
    }
}

# ---- 版本工具 ----
function To-Ver([string]$v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    $v = ($v -replace '^[vV]', '').Trim()
    if ($v -match '^(\d+(?:\.\d+){0,3})') { try { return [version]$Matches[1] } catch { return $null } }
    return $null
}
function Ver-Newer([string]$latest, [string]$cached) {
    $a = To-Ver $latest; $b = To-Ver $cached
    if (-not $a) { return $false }
    if (-not $b) { return $true }
    return ($a -gt $b)
}
function Get-LatestGitHubTag([string]$repo) {
    foreach ($api in @("https://api.github.com/repos/$repo/releases/latest",
                       "https://ghfast.top/https://api.github.com/repos/$repo/releases/latest")) {
        try {
            $r = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'tabby-setup' } -UseBasicParsing -TimeoutSec 12
            if ($r.tag_name) { return [string]$r.tag_name }
        } catch { }
    }
    return $null
}
function Get-LatestNodeLts {
    try {
        $idx = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing -TimeoutSec 12
        $lts = $idx | Where-Object { $_.lts } | Select-Object -First 1
        if ($lts) { return [string]$lts.version }
    } catch { }
    return $null
}
function Get-CachedModuleVersion {
    param([string]$CacheDir, [string]$Name)
    $d = Join-Path $CacheDir "modules\$Name"
    if (Test-Path $d) {
        $psd1 = Get-ChildItem $d -Recurse -Filter "$Name.psd1" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($psd1) { try { return [string]((Import-PowerShellDataFile $psd1.FullName).ModuleVersion) } catch { } }
    }
    return $null
}

# ---- zip/msix 完整性校验（截断的 zip 打不开中央目录）----
function Test-ZipFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $null = $z.Entries.Count
        $z.Dispose()
        return $true
    } catch { return $false }
}

# ---- 单个文件型组件的来源决策：cache / online / skip ----
function Resolve-Source {
    param(
        [string]$Key,
        [string]$CacheDir,
        [hashtable]$Preference,
        [ValidateSet('ask', 'cache', 'online')][string]$Mode = 'ask'
    )
    $file = Get-CachePath $CacheDir $Key
    $has = $file -and (Test-Path $file) -and ((Get-Item $file).Length -gt 0)
    if ($Mode -eq 'online') { return 'online' }
    if ($Preference -and $Preference.ContainsKey($Key)) {
        switch ($Preference[$Key]) {
            'skip'   { return 'skip' }
            'latest' { return 'online' }
            'cache'  { if ($has) { return 'cache' } else { return 'online' } }
        }
    }
    if ($Mode -eq 'cache') { if ($has) { return 'cache' } else { return 'skip' } }
    if ($has) { return 'cache' }
    return 'online'
}

# ---- 网络连通性探测（任一可靠端点有 HTTP 响应即视为在线）----
function Test-Network {
    foreach ($u in @('https://api.github.com/', 'https://ghfast.top/')) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $req = [System.Net.HttpWebRequest]::Create($u)
            $req.UserAgent = 'tabby-setup'
            $req.Method = 'HEAD'
            $req.Timeout = 5000
            $req.AllowAutoRedirect = $true
            $resp = $req.GetResponse()
            $resp.Close()
            return $true
        } catch {
            if ($_.Exception.Response) { return $true }   # 有 HTTP 响应(如 403/404)也说明网络是通的
        }
    }
    return $false
}

# ---- 版本检查（默认全自动；只有“检测到更新”才询问）----
#   返回 key->'cache'|'latest'|'skip' 的偏好表；取消返回 @{__cancel=$true}
#   规则：
#     - 无离线包 + 有网  -> 自动在线下载（不询问）
#     - 无离线包 + 无网  -> 提示并取消
#     - 有离线包 + 无网  -> 提示“无网络，用默认离线安装”并继续（不询问）
#     - 有离线包 + 有网 + 无更新 -> 直接用离线包（不询问）
#     - 有离线包 + 有网 + 有更新 -> 才弹出选择（默认已准备版本）
function Invoke-VersionCheck {
    param(
        [string]$CacheDir,
        $Manifest,
        [ValidateSet('ask', 'cache', 'online')][string]$Mode,
        [bool]$Yes
    )
    if ($Mode -ne 'ask') { return @{} }

    $hasAnyCache = (Test-Path $CacheDir) -and (@(Get-ChildItem $CacheDir -File -ErrorAction SilentlyContinue).Count -gt 0)
    $online = Test-Network

    # ---- A. 没有离线包 ----
    if (-not $hasAnyCache) {
        Write-Host ''
        if ($online) {
            Write-Host '  [离线包] 未发现 cache\，将直接联网下载安装（镜像优先，进度实时显示）。' -ForegroundColor Yellow
            return @{}
        }
        Write-Host '  [离线包] 未发现 cache\，且未检测到网络连接。' -ForegroundColor Red
        Write-Host '           请先在有网络的机器上运行 prefetch.cmd 准备离线包，' -ForegroundColor Yellow
        Write-Host '           再把整个 tools\tabby-setup 文件夹拷贝过来，然后运行 install.cmd。' -ForegroundColor Yellow
        return @{ __cancel = $true }
    }

    # ---- B/C. 有离线包：收集组件（有网才查上游最新版）并显示版本对照 ----
    $rows = New-Object System.Collections.ArrayList
    $comps = @(
        @{ key = 'tabby'; name = 'Tabby';                 repo = 'Eugeny/tabby' },
        @{ key = 'font';  name = 'JetBrainsMono NF';      repo = 'ryanoasis/nerd-fonts' },
        @{ key = 'pwsh';  name = 'PowerShell 7';          repo = 'PowerShell/PowerShell' },
        @{ key = 'omp';   name = 'oh-my-posh';            repo = 'JanDedobbeleer/oh-my-posh' }
    )
    foreach ($c in $comps) {
        $file = Get-CachePath $CacheDir $c.key
        $cached = $null
        if ($Manifest -and $Manifest.($c.key)) { $cached = [string]$Manifest.($c.key).version }
        $has = (Test-Path $file) -and ((Get-Item $file).Length -gt 0)
        if (-not $has -and -not $cached) { continue }
        $latest = if ($online) { Get-LatestGitHubTag $c.repo } else { $null }
        [void]$rows.Add(@{ key = $c.key; name = $c.name; cached = $cached; latest = $latest; has = $has })
    }
    $nodeFile = Get-CachePath $CacheDir 'node'
    $nodeCached = $null
    if ($Manifest -and $Manifest.node) { $nodeCached = [string]$Manifest.node.version }
    if ((Test-Path $nodeFile) -or $nodeCached) {
        $nodeLatest = if ($online) { Get-LatestNodeLts } else { $null }
        [void]$rows.Add(@{ key = 'node'; name = 'Node.js'; cached = $nodeCached; latest = $nodeLatest; has = (Test-Path $nodeFile) })
    }
    foreach ($mn in @('PSReadLine', 'CompletionPredictor')) {
        $cv = Get-CachedModuleVersion $CacheDir $mn
        if ($cv) {
            $lv = $null
            if ($online) { try { $lv = [string](Find-Module -Name $mn -ErrorAction Stop).Version } catch { } }
            [void]$rows.Add(@{ key = $mn; name = $mn; cached = $cv; latest = $lv; has = $true })
        }
    }
    if ((Test-Path (Join-Path $CacheDir 'npm\node_modules')) -or (Test-Path (Join-Path $CacheDir 'npm\node_modules.zip'))) {
        [void]$rows.Add(@{ key = 'npm'; name = 'npm 插件'; cached = '(已准备)'; latest = $null; has = $true })
    }

    $anyNewer = $false
    foreach ($r in $rows) {
        if ($r.latest -and (Ver-Newer $r.latest $r.cached)) { $anyNewer = $true }
    }

    # ---- 始终显示版本明细（无论是否有更新/是否有网）----
    Write-Host ''
    Write-Host '  ========== 离线包版本检查 ==========' -ForegroundColor Cyan
    Write-Host ('  {0,-20} {1,-16} {2,-16} {3}' -f '组件', '已准备', '最新', '状态')
    Write-Host ('  ' + ('-' * 68)) -ForegroundColor DarkGray
    foreach ($r in $rows) {
        if (-not $online)         { $st = '(未联网检测)' }
        elseif ($r.latest -and (Ver-Newer $r.latest $r.cached)) { $st = '^ 有更新' }
        elseif ($r.latest)        { $st = '最新' }
        else                      { $st = '(未查到)' }
        if (-not $r.has) { $st = '文件缺失' }
        $cv = if ($r.cached) { $r.cached } else { '-' }
        $lv = if ($r.latest) { $r.latest } else { '-' }
        $color = if ($st -eq '^ 有更新') { 'Yellow' } elseif ($st -eq '最新') { 'Green' } elseif ($st -eq '文件缺失') { 'Red' } else { 'Gray' }
        Write-Host ('  {0,-20} {1,-16} {2,-16} {3}' -f $r.name, $cv, $lv, $st) -ForegroundColor $color
    }
    Write-Host ''

    # ---- 无网络：默认离线安装（版本已在上表显示）----
    if (-not $online) {
        Write-Host '  [离线包] 未检测到网络，使用已准备的离线包默认安装（跳过在线更新检查）。' -ForegroundColor Yellow
        return @{}
    }

    # ---- 有网但无更新：直接离线安装，不询问 ----
    if (-not $anyNewer) {
        Write-Host '  [离线包] 已是最新，直接使用离线包安装。' -ForegroundColor Green
        return @{}
    }

    # ---- 有更新：询问 ----
    Write-Host '  [!] 检测到新版本。从 GitHub 直连下载可能很慢（每项可能数分钟）' -ForegroundColor Yellow
    Write-Host '   [1] * 全部使用已准备版本（推荐：离线、秒装）'
    Write-Host '   [2]   全部在线下载最新版本（慢）'
    Write-Host '   [3]   逐个选择'
    $choice = if ($Yes) { '1' } else { Read-Host '  选择 1-3 (Enter = 1)' }

    if ($choice -eq '2') {
        $pref = @{}
        foreach ($r in $rows) { $pref[$r.key] = 'latest' }
        return $pref
    }
    if ($choice -eq '3') {
        $pref = @{}
        foreach ($r in $rows) {
            if (-not ($r.latest -and (Ver-Newer $r.latest $r.cached))) {
                if ($r.has) { $pref[$r.key] = 'cache' } else { $pref[$r.key] = 'latest' }
                continue
            }
            Write-Host ''
            Write-Host ("  " + $r.name + ": 已准备 " + $r.cached + " / 最新 " + $r.latest) -ForegroundColor Cyan
            Write-Host '   [1] 用已准备版本（推荐）   [2] 在线下最新（慢）   [3] 跳过'
            $a = Read-Host '   选择 1-3 (Enter = 1)'
            if ($a -eq '2') { $pref[$r.key] = 'latest' }
            elseif ($a -eq '3') { $pref[$r.key] = 'skip' }
            else { $pref[$r.key] = 'cache' }
        }
        return $pref
    }
    $pref = @{}
    foreach ($r in $rows) { $pref[$r.key] = 'cache' }
    return $pref
}
