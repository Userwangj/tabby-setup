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
        [string]$LogFile = '',
        [switch]$MirrorMode,
        [switch]$Resume
    )
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # 续传：已存在的不完整文件作为起点（服务器需支持 Range，返回 206）
        $existing = 0
        if ($Resume -and (Test-Path $OutFile)) {
            try { $existing = [long](Get-Item $OutFile).Length } catch { $existing = 0 }
            if ($existing -gt 0 -and $ExpectedBytes -gt 0 -and $existing -eq $ExpectedBytes) { return $true }
        }
        $resp = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $req = [System.Net.HttpWebRequest]::Create($Url)
                $req.UserAgent = 'tabby-setup'
                $req.Timeout = $TimeoutSec * 1000
                $req.ReadWriteTimeout = $TimeoutSec * 1000
                $req.AllowAutoRedirect = $true
                try { $req.ServicePoint.Expect100Continue = $false } catch { }
                if ($existing -gt 0) { try { $req.AddRange([int]$existing) } catch { $existing = 0 } }
                $resp = $req.GetResponse()
                break
            } catch {
                if ($attempt -ge 3) { throw }
                Start-Sleep -Seconds (2 * $attempt)
            }
        }
        $status = 0
        try { $status = [int]$resp.StatusCode } catch { $status = 0 }
        $resuming = ($existing -gt 0 -and $status -eq 206)
        if ($existing -gt 0 -and -not $resuming) { $existing = 0 }   # 服务器不支持续传 → 重下
        $total = $resp.ContentLength
        if ($resuming -and $total -gt 0) { $total = $existing + $total }  # 还原完整文件大小
        if ($total -le 0 -and $ExpectedBytes -gt 0) { $total = $ExpectedBytes }
        $in = $resp.GetResponseStream()
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($resuming) {
            $out = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
        } else {
            if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
            $out = [System.IO.File]::Create($OutFile)
        }
        $lastLog = [datetime]::MinValue
        $lastPct = -100
        if ($LogFile) { Add-Content -Path $LogFile -Value ("$((Get-Date).ToString('HH:mm:ss'))  START  $Activity  <- $Url") -Encoding UTF8 -ErrorAction SilentlyContinue }
        try {
            $buffer = New-Object byte[] 131072
            $sum = $existing
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
        if (-not (Test-Path $OutFile)) { $script:LastDownloadError = '文件未生成'; return $false }
        $len = (Get-Item $OutFile).Length
        if ($total -gt 0 -and $len -ne $total) {
            $script:LastDownloadError = ("Incomplete download ($([math]::Round($len/1MB,1)) / $([math]::Round($total/1MB,1)) MB)")
            if (-not $MirrorMode -and (Get-Command Warn -ErrorAction SilentlyContinue)) { Warn "       $($script:LastDownloadError)" }
            if (-not $Resume) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
            return $false
        }
        if ($ExpectedBytes -gt 0 -and $len -ne $ExpectedBytes) {
            $script:LastDownloadError = ("Size mismatch (got $len, expected $ExpectedBytes bytes)")
            if (-not $MirrorMode -and (Get-Command Warn -ErrorAction SilentlyContinue)) { Warn "       $($script:LastDownloadError)" }
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        if ($MinBytes -gt 0 -and $len -lt $MinBytes) { $script:LastDownloadError = ("文件过小（$len 字节）"); if (-not $Resume) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }; return $false }
        return $true
    } catch {
        $script:LastDownloadError = $_.Exception.Message
        if (-not $MirrorMode) {
            try { Complete-LiveProgress "   $Activity   失败" } catch { }
            if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn "       Download error: $($_.Exception.Message)" }
        }
        # 最后兜底：curl（静默），应对个别 URL 的 TLS/代理握手问题
        $before = 0
        if (Test-Path $OutFile) { try { $before = [long](Get-Item $OutFile).Length } catch { $before = 0 } }
        try {
            curl.exe -L -s -m $TimeoutSec --retry 3 --retry-delay 2 -o $OutFile $Url
            if (Test-Path $OutFile) {
                $clen = [long](Get-Item $OutFile).Length
                # 已知精确大小则以其为准；否则要求本次确有进展，避免残留旧文件被误判为成功
                if ($ExpectedBytes -gt 0) {
                    $okCurl = ($clen -eq $ExpectedBytes)
                } elseif ($MinBytes -gt 0) {
                    $okCurl = (($clen -ge $MinBytes) -and (($clen -gt $before) -or ($before -eq 0)))
                } else {
                    $okCurl = (($clen -gt $before) -or ($before -eq 0 -and $clen -gt 0))
                }
                if ($okCurl) { return $true }
            }
        } catch { }
        # 失败：清理残留（续传模式保留不完整文件以便下次继续）
        if (-not $Resume) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

# ---- 多镜像下载：逐个尝试，失败时提示「切换下一个镜像」 ----
# ============================================================
#  多线程分段下载（HTTP Range 206 + 并行 + 断点续传）
#  需要镜像支持 Range；不支持、文件较小或任一段失败则返回 $false，
#  由调用方回退到单流下载。
#  并发数可用环境变量 TABBY_SETUP_CONNECTIONS 覆盖（默认 6；设 1 即禁用分段）。
# ============================================================
function Get-FileSegmented {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [long]$ExpectedBytes = 0,
        [int]$Connections = 6,
        [int]$TimeoutSec = 900,
        [long]$MinBytes = 16MB,
        [string]$Activity = 'Download',
        [string]$LogFile = ''
    )
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # 1) 探测总大小 & 是否支持 Range（bytes=0-0 → 206 + Content-Range）
        $total = 0
        try {
            $preq = [System.Net.HttpWebRequest]::Create($Url)
            $preq.UserAgent = 'tabby-setup'
            $preq.AllowAutoRedirect = $true
            $preq.Timeout = 30000
            $preq.ReadWriteTimeout = 30000
            try { $preq.ServicePoint.Expect100Continue = $false } catch { }
            try { $preq.AddRange(0, 0) } catch { }
            $presp = $preq.GetResponse()
            $pstatus = 0; try { $pstatus = [int]$presp.StatusCode } catch { }
            if ($pstatus -eq 206) {
                $cr = [string]$presp.Headers['Content-Range']
                if ($cr -match '/(\d+)\s*$') { $total = [long]$Matches[1] }
            }
            $presp.Close()
        } catch { }
        if ($total -le 0 -and $ExpectedBytes -gt 0) { $total = $ExpectedBytes }
        if ($total -le 0) { return $false }
        if ($total -lt $MinBytes) { return $false }

        # 已完成：清理残留分段并直接成功
        if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -eq $total)) {
            Get-ChildItem ($OutFile + '.*.part*') -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            return $true
        }

        # 2) 划分分段
        $conn = [int]$Connections
        if ($conn -lt 1) { $conn = 1 }
        if ($conn -gt 16) { $conn = 16 }
        $segLen = [long][Math]::Ceiling($total / $conn)
        $ranges = @()
        for ($i = 0; $i -lt $conn; $i++) {
            $s = [long]$i * $segLen
            if ($s -ge $total) { break }
            $e = [long][Math]::Min($total - 1, $s + $segLen - 1)
            $ranges += , @($s, $e)
        }
        if ($ranges.Count -le 1) { return $false }   # 仅一段，单流即可

        $partOf = {
            param($url, $start, $end, $partPath, $timeoutSec)
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $want = $end - $start + 1
                $existing = 0
                if (Test-Path $partPath) { try { $existing = [long](Get-Item $partPath).Length } catch { $existing = 0 } }
                if ($existing -eq $want) { return $true }
                if ($existing -gt $want) { $existing = 0 }
                $req = [System.Net.HttpWebRequest]::Create($url)
                $req.UserAgent = 'tabby-setup'
                $req.Timeout = $timeoutSec * 1000
                $req.ReadWriteTimeout = $timeoutSec * 1000
                $req.AllowAutoRedirect = $true
                try { $req.ServicePoint.Expect100Continue = $false } catch { }
                try { $req.AddRange($start + $existing, $end) } catch { return $false }
                $resp = $req.GetResponse()
                $status = 0; try { $status = [int]$resp.StatusCode } catch { }
                if ($status -ne 206) { try { $resp.Close() } catch { }; return $false }
                $in = $resp.GetResponseStream()
                if ($existing -le 0 -and (Test-Path $partPath)) { Remove-Item $partPath -Force -ErrorAction SilentlyContinue }
                $mode = if ($existing -gt 0) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
                $out = [System.IO.File]::Open($partPath, $mode, [System.IO.FileAccess]::Write)
                try {
                    $buf = New-Object byte[] 262144
                    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n) }
                } finally { $out.Close(); $in.Close(); $resp.Close() }
                return ((Get-Item $partPath).Length -eq $want)
            } catch { return $false }
        }

        if ($LogFile) { Add-Content -Path $LogFile -Value ("$((Get-Date).ToString('HH:mm:ss'))  SEG $($ranges.Count)conn  $Activity  <- $Url") -Encoding UTF8 -ErrorAction SilentlyContinue }
        if (Get-Command Info -ErrorAction SilentlyContinue) { Info ("      多线程分段下载：{0} 段并发，共 {1:N1} MB ..." -f $ranges.Count, ($total / 1MB)) }

        $jobs = @(); $parts = @()
        for ($i = 0; $i -lt $ranges.Count; $i++) {
            $pp = ("{0}.{1}.part{2}" -f $OutFile, $total, $i)
            $parts += $pp
            $jobs += Start-Job -ScriptBlock $partOf -ArgumentList $Url, $ranges[$i][0], $ranges[$i][1], $pp, $TimeoutSec
        }

        # 轮询各分段文件大小，实时刷新进度条（与单流下载同一套渲染）
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $deadline = (Get-Date).AddSeconds($TimeoutSec + 120)
        while ($true) {
            $running = @($jobs | Where-Object { $_.State -eq 'Running' })
            $sum = 0
            foreach ($pp in $parts) { if (Test-Path $pp) { try { $sum += [long](Get-Item $pp).Length } catch { } } }
            if ($sum -gt $total) { $sum = $total }
            $spdVal = if ($sw.Elapsed.TotalSeconds -gt 0) { $sum / $sw.Elapsed.TotalSeconds } else { 0 }
            $pct = [int](($sum / $total) * 100); if ($pct -gt 100) { $pct = 100 }
            $eta = ''
            if ($spdVal -gt 1024) {
                $remain = ($total - $sum) / $spdVal
                if ($remain -ge 0 -and $remain -lt 86400) { $eta = 'ETA ' + ([TimeSpan]::FromSeconds([int]$remain)).ToString('mm\:ss') }
            }
            try { Write-LiveProgress (New-ProgressLine -Activity $Activity -Pct $pct -MbText ("{0:N1}/{1:N1} MB" -f ($sum / 1MB), ($total / 1MB)) -Spd (Format-Speed $spdVal) -Eta $eta) } catch { }
            if ($running.Count -eq 0) { break }
            if ((Get-Date) -gt $deadline) { break }
            Start-Sleep -Milliseconds 1000
        }
        $null = Wait-Job -Job $jobs -Timeout 5
        $allOk = $true
        foreach ($j in $jobs) {
            if ($j.State -eq 'Completed') {
                $r = Receive-Job -Job $j -ErrorAction SilentlyContinue
                if (-not ($r -eq $true)) { $allOk = $false }
            } else { $allOk = $false; Stop-Job -Job $j -ErrorAction SilentlyContinue }
        }
        Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
        if (-not $allOk) {
            try { Complete-LiveProgress ("   $Activity   分段下载未完成") } catch { }
            if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn '      回退单流下载（分段已保留，可续传）。' }
            return $false
        }
        $sum = 0
        foreach ($pp in $parts) { if (Test-Path $pp) { try { $sum += [long](Get-Item $pp).Length } catch { } } }
        try { Complete-LiveProgress (New-ProgressLine -Activity $Activity -Pct 100 -MbText ("{0:N1}/{1:N1} MB" -f ($sum / 1MB), ($total / 1MB)) -Spd (Format-Speed $(if ($sw.Elapsed.TotalSeconds -gt 0) { $sum / $sw.Elapsed.TotalSeconds } else { 0 })) -Eta '') } catch { }

        # 3) 合并并校验
        try { Write-LiveProgress ("   $Activity   合并中...") } catch { }
        $tmpOut = $OutFile + '.joining'
        try {
            $out = [System.IO.File]::Create($tmpOut)
            try {
                foreach ($pp in $parts) {
                    if (-not (Test-Path $pp)) { throw ('缺少分段 ' + $pp) }
                    $fin = [System.IO.File]::OpenRead($pp)
                    try { $fin.CopyTo($out) } finally { $fin.Close() }
                }
            } finally { $out.Close() }
        } catch {
            Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
            try { Complete-LiveProgress ("   $Activity   合并失败") } catch { }
            return $false
        }
        if ((Get-Item $tmpOut).Length -ne $total) {
            Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
            try { Complete-LiveProgress ("   $Activity   合并失败") } catch { }
            return $false
        }
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
        Move-Item -Path $tmpOut -Destination $OutFile -Force
        foreach ($pp in $parts) { Remove-Item $pp -Force -ErrorAction SilentlyContinue }
        if ($ExpectedBytes -gt 0 -and (Get-Item $OutFile).Length -ne $ExpectedBytes) {
            try { Complete-LiveProgress ("   $Activity   校验失败") } catch { }
            return $false
        }
        try { Complete-LiveProgress ("   $Activity   完成   $([math]::Round((Get-Item $OutFile).Length / 1MB, 1)) MB") } catch { }
        return $true
    } catch {
        return $false
    }
}

function Get-FileFromMirrors {
    param(
        [string[]]$Urls,
        [string]$OutFile,
        [long]$MinBytes = 0,
        [long]$ExpectedBytes = 0,
        [int]$TimeoutSec = 600,
        [string]$Activity = 'Download',
        [string]$LogFile = ''
    )
    $list = @($Urls)
    $n = $list.Count

    # 大文件优先尝试多线程分段下载（需镜像支持 Range）；任一镜像成功即返回
    $segThreshold = 16MB
    if ($ExpectedBytes -ge $segThreshold -or $MinBytes -ge $segThreshold) {
        $conns = 6
        if ($env:TABBY_SETUP_CONNECTIONS) { try { $conns = [int]$env:TABBY_SETUP_CONNECTIONS } catch { $conns = 6 } }
        if ($conns -gt 1) {
            foreach ($u in $list) {
                if (Get-FileSegmented -Url $u -OutFile $OutFile -ExpectedBytes $ExpectedBytes -Connections $conns -TimeoutSec $TimeoutSec -MinBytes $segThreshold -Activity $Activity -LogFile $LogFile) {
                    return $true
                }
            }
        }
    }

    for ($i = 0; $i -lt $n; $i++) {
        $u = $list[$i]
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn ("       Downloading ({0}/{1}): {2}" -f ($i + 1), $n, $u) }
        if (Get-FileWithProgress -Url $u -OutFile $OutFile -MinBytes $MinBytes -ExpectedBytes $ExpectedBytes -TimeoutSec $TimeoutSec -Activity $Activity -LogFile $LogFile -MirrorMode -Resume) {
            Get-ChildItem ($OutFile + '.*.part*') -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            return $true
        }
        if (($i + 1) -lt $n) {
            if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn ("       镜像 {0}/{1} 不可用，切换下一个…" -f ($i + 1), $n) }
        } else {
            $reason = ''
            if ($script:LastDownloadError) { $reason = "。最后错误：$($script:LastDownloadError)" }
            if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn ("       所有镜像均无法下载（共 {0} 个）{1}" -f $n, $reason) }
        }
    }
    # 全部镜像失败：清理续传残留，避免被后续的大小下限误判为有效
    Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
    return $false
}

# ---- 下载镜像顺序（改这里即可全局调整）----
# 直连优先，其次公共反代；已移除常连接重置的 ghfast.top。
function Get-GitHubMirrors {
    param([Parameter(Mandatory)][string]$DirectUrl)
    return @(
        $DirectUrl,
        "https://gh-proxy.com/$DirectUrl",
        "https://ghproxy.net/$DirectUrl"
    )
}
function Get-GitHubApiMirrors {
    param([Parameter(Mandatory)][string]$ApiUrl)
    return @(
        $ApiUrl,
        "https://gh-proxy.com/$ApiUrl",
        "https://ghproxy.net/$ApiUrl"
    )
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

# ---- 交互式“显式选择”：必须输入 Allowed 之一；回车/无效会重问，防止误触回车 ----
# 返回小写后的选项字符串；连续 MaxTries 次无效则返回 DefaultOnFail（默认取 Allowed[0]）。
function Read-Choice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string[]]$Allowed,
        [string]$DefaultOnFail = '',
        [int]$MaxTries = 5
    )
    if ([string]::IsNullOrEmpty($DefaultOnFail)) { $DefaultOnFail = $Allowed[0] }
    $allowedTxt = ($Allowed -join ' / ')
    for ($i = 0; $i -lt $MaxTries; $i++) {
        $ans = ''
        try { $ans = Read-Host $Prompt } catch { $ans = '' }
        $v = ([string]$ans).Trim().ToLowerInvariant()
        if ($Allowed -contains $v) { return $v }
        if ([string]::IsNullOrWhiteSpace($v)) {
            Write-Host ('   请直接输入 ' + $allowedTxt + '（不要直接回车）。') -ForegroundColor Yellow
        } else {
            Write-Host ('   无效输入，请输入 ' + $allowedTxt + '。') -ForegroundColor Yellow
        }
    }
    Write-Host ('   多次无效输入，默认按 ' + $DefaultOnFail + ' 处理。') -ForegroundColor Yellow
    return $DefaultOnFail
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
    foreach ($api in (Get-GitHubApiMirrors "https://api.github.com/repos/$repo/releases/latest")) {
        try {
            $r = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'tabby-setup' } -UseBasicParsing -TimeoutSec 12
            if ($r.tag_name) { return [string]$r.tag_name }
        } catch { }
    }
    return $null
}

# ============================================================
#  缓存包 Release 发布 / 拉取
#  把整份 cache\ 打包成 cache-bundle.zip 传到 GitHub Release；
#  目标机可一键拉取（走镜像、支持断点续传），无需逐项挑选。
#  发布仓库默认本包仓库，可用环境变量 TABBY_SETUP_REPO 覆盖。
# ============================================================
$script:CacheBundleName  = 'cache-bundle.zip'
$script:CacheReleaseRepo = 'Userwangj/tabby-setup'

function Get-CacheReleaseRepo {
    if ($env:TABBY_SETUP_REPO) { return [string]$env:TABBY_SETUP_REPO }
    return $script:CacheReleaseRepo
}

# 查询缓存包 Release（默认最新；未发布 / 无附件返回 $null）
function Get-CacheReleaseInfo {
    param([string]$Repo = '', [string]$Tag = '')
    if (-not $Repo) { $Repo = Get-CacheReleaseRepo }
    $api = if ($Tag) { "https://api.github.com/repos/$Repo/releases/tags/$Tag" } else { "https://api.github.com/repos/$Repo/releases/latest" }
    foreach ($u in (Get-GitHubApiMirrors $api)) {
        try {
            $r = Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent' = 'tabby-setup' } -UseBasicParsing -TimeoutSec 15
            if (-not $r.tag_name) { continue }
            $asset = @($r.assets) | Where-Object { $_.name -eq $script:CacheBundleName } | Select-Object -First 1
            return [pscustomobject]@{
                Repo     = $Repo
                Tag      = [string]$r.tag_name
                HasAsset = [bool]$asset
                Name     = if ($asset) { [string]$asset.name } else { $script:CacheBundleName }
                Size     = if ($asset) { [long]$asset.size } else { 0 }
                Url      = if ($asset) { [string]$asset.browser_download_url } else { '' }
            }
        } catch { }
    }
    return $null
}

# 从 Release 下载整份缓存包并解压到 cache\；成功返回 $true
function Get-CacheBundleFromRelease {
    param([string]$CacheDir, [string]$Tag = '', [string]$Repo = '')
    if (-not $Repo) { $Repo = Get-CacheReleaseRepo }
    $rel = Get-CacheReleaseInfo -Repo $Repo -Tag $Tag
    if (-not $rel -or -not $rel.HasAsset) { return $false }

    $tmp = Join-Path $env:TEMP 'tabby-setup-cache-bundle.zip'
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $urls = Get-GitHubMirrors $rel.Url
    $ok = Get-FileFromMirrors -Urls $urls -OutFile $tmp -ExpectedBytes $rel.Size -MinBytes 1MB -Activity ('缓存包 ' + $rel.Tag) -TimeoutSec 1800
    if (-not $ok) { return $false }
    if ($rel.Size -gt 0 -and (Get-Item $tmp).Length -ne $rel.Size) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }
    if (-not (Test-ZipFile $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return $false }

    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    $cacheFull = [System.IO.Path]::GetFullPath($CacheDir).TrimEnd('\') + '\'
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
    try {
        foreach ($e in $zip.Entries) {
            if ([string]::IsNullOrEmpty($e.Name)) { continue }   # 目录项
            $entryRel = ($e.FullName -replace '/', '\')
            $dest = [System.IO.Path]::GetFullPath((Join-Path $CacheDir $entryRel))
            if (-not $dest.StartsWith($cacheFull, [System.StringComparison]::OrdinalIgnoreCase)) { continue }  # 防 zip-slip
            $dir = Split-Path -Parent $dest
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
        }
    } finally { $zip.Dispose() }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $true
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
    foreach ($u in @('https://api.github.com/', 'https://gh-proxy.com/')) {
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
            Write-Host '  [离线包] 未发现 cache\，将先批量预下载缺失组件，再离线安装（直连优先、自动切镜像）。' -ForegroundColor Yellow
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
    Write-Host '   [2]   只在线更新「有更新」的组件，其余用已准备版本'
    Write-Host '   [3]   逐个选择'
    $choice = if ($Yes) { '1' } else { Read-Choice -Prompt '  选择 1-3' -Allowed @('1', '2', '3') -DefaultOnFail '1' }

    if ($choice -eq '2') {
        # 只有「有更新」的组件才联网下最新；已是最新的用缓存（无文件时 Resolve-Source 会自动回退联网）
        $pref = @{}
        foreach ($r in $rows) {
            if ($r.latest -and (Ver-Newer $r.latest $r.cached)) { $pref[$r.key] = 'latest' }
            else { $pref[$r.key] = 'cache' }
        }
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
            $a = Read-Choice -Prompt '   选择 1-3' -Allowed @('1', '2', '3') -DefaultOnFail '1'
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
