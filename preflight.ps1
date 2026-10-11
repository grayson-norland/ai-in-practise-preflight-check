# Pre-flight check for the AI in Practice session: Windows PowerShell version.
# (macOS / Linux / WSL / Git Bash: use preflight.sh instead.)
#
#   powershell -ExecutionPolicy Bypass -File .\preflight.ps1
#
# It runs a few tiny hello-world containers, changes nothing on your machine
# apart from Docker's image cache, and writes preflight-report.txt.
# Works in Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $PSScriptRoot

$Port    = 8085
$Project = 'preflight-check'
$Report  = Join-Path $PSScriptRoot 'preflight-report.txt'
Set-Content -LiteralPath $Report -Value '' -Encoding UTF8
$script:Fails = New-Object System.Collections.ArrayList
$script:Warns = New-Object System.Collections.ArrayList
$script:Log   = ''

function Say($text, $color) {
    if ($color) { Write-Host $text -ForegroundColor $color } else { Write-Host $text }
    Add-Content -LiteralPath $Report -Value $text -Encoding UTF8
}
function Ok($text)   { Write-Host '  [' -NoNewline; Write-Host ' OK ' -ForegroundColor Green -NoNewline; Write-Host "] $text"
                       Add-Content -LiteralPath $Report -Value "  [ OK ] $text" -Encoding UTF8 }
function Warn($text) { Write-Host '  [' -NoNewline; Write-Host 'WARN' -ForegroundColor Yellow -NoNewline; Write-Host "] $text"
                       Add-Content -LiteralPath $Report -Value "  [WARN] $text" -Encoding UTF8
                       [void]$script:Warns.Add($text) }
function Bad($text)  { Write-Host '  [' -NoNewline; Write-Host 'FAIL' -ForegroundColor Red -NoNewline; Write-Host "] $text"
                       Add-Content -LiteralPath $Report -Value "  [FAIL] $text" -Encoding UTF8
                       [void]$script:Fails.Add($text) }
function Note($text) { Write-Host "         $text"; Add-Content -LiteralPath $Report -Value "         $text" -Encoding UTF8 }

# Run a program, capture stdout+stderr together, return the exit code.
# (Process object instead of "2>&1": Windows PowerShell 5.1 wraps stderr lines in error records.)
function Invoke-Native([string]$exe, [string[]]$arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $quoted = $arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
    $psi.Arguments = ($quoted -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $script:Log = $_.Exception.Message
        return 127
    }
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $script:Log = $so.Result + "`n" + $se.Result
    return $p.ExitCode
}

function Explain {
    $lines = $script:Log -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 10
    foreach ($l in $lines) { Note "| $l" }
    $t = $script:Log
    if ($t -match 'Cannot connect to the Docker daemon|failed to connect to the docker API|error during connect|Is the docker daemon running|pipe/docker_engine|dockerDesktopLinuxEngine') {
        Note '-> Docker is installed but not running. Start Docker Desktop, wait until it says running, then re-run.' }
    if ($t -match 'permission denied|Access is denied') {
        Note '-> Permission problem talking to Docker. Make sure Docker Desktop is running and your user is allowed to use it.' }
    if ($t -match 'error getting credentials|credential helper|docker-credential') {
        Note '-> Docker''s credential helper failed. Restart Docker Desktop; if it persists, remove the "credsStore" line from %USERPROFILE%\.docker\config.json.' }
    if ($t -match 'toomanyrequests|rate limit') {
        Note '-> Docker Hub rate limit. Run "docker login" with a free account and re-run.' }
    if ($t -match 'no matching manifest|exec format error') {
        Note '-> Architecture mismatch. Tell the organiser exactly what this screen says (and your PC model).' }
    if ($t -match 'x509|certificate verify failed|SSL certificate problem|unable to get local issuer') {
        Note '-> Certificate error: usually a company proxy or VPN that re-signs traffic. Try off-VPN, or ask IT for the proxy CA.' }
    if ($t -match 'name resolution|no such host|i/o timeout|Could not resolve|timed out|Timeout|TLS handshake|Failed to fetch|Temporary failure') {
        Note '-> Network problem reaching the internet from Docker. Check VPN / proxy / Wi-Fi and re-run.' }
    if ($t -match 'no space left') {
        Note '-> Docker is out of disk space. Try "docker system prune" (removes unused images/containers) and re-run.' }
}

function Test-PortBusy {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(1000, $false) -and $c.Connected) { return $true }
        return $false
    } catch { return $false } finally { $c.Close() }
}

function Get-HttpLine {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 3
        return "HTTP $($r.StatusCode)"
    } catch {
        if ($_.Exception.Response) { return 'HTTP' }   # any HTTP answer at all counts
        return ''
    }
}

# --------------------------------------------------------------------------
Say ''
Say '============================================================='
Say '  PRE-FLIGHT CHECK'
Say '============================================================='
Say ("  {0}   Windows PowerShell {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $PSVersionTable.PSVersion)
Say ''
Say '  This will:'
Say '    - check that Docker is installed, running, and set up correctly on this machine'
Say '    - download a few hundred MB of container images (the same ones the real session uses)'
Say '    - build two small placeholder containers, so those downloads and installs are cached'
Say "    - briefly start a test web server on port $Port, then stop everything"
Say ''
Say '  It does not touch any of your other files, and nothing is left running afterwards.'
Say ''
$answer = Read-Host '  Continue? [Y/n]'
if ($answer -match '^(?i:n|no)$') {
    Say ''
    Say '  Cancelled - nothing was changed.'
    exit 0
}
Say ''

# ---- 1. Docker installed / running ---------------------------------------
Say '1. Docker'
$dockerOk = $false
$darch = ''
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Bad 'docker command not found'
    Note '-> Install Docker Desktop for Windows: https://docs.docker.com/desktop/setup/install/windows-install/'
} else {
    [void](Invoke-Native 'docker' @('--version'))
    Ok ("docker command found: " + $script:Log.Trim())
    $rc = Invoke-Native 'docker' @('info')
    if ($rc -ne 0) {
        Bad 'Docker is installed but not running'
        $script:Log = (($script:Log -split "`r?`n") | Where-Object { $_ -match 'error|failed|cannot|denied|not found|could not' }) -join "`n"
        Explain
    } else {
        [void](Invoke-Native 'docker' @('info', '--format', '{{.OSType}}|{{.Architecture}}|{{.MemTotal}}|{{.ServerVersion}}'))
        $parts = $script:Log.Trim().Split('|')
        $ostype = $parts[0]; $darch = $parts[1]; $mem = 0; [void][int64]::TryParse($parts[2], [ref]$mem)
        Ok "Docker is running (engine $($parts[3]), $ostype/$darch)"
        $dockerOk = $true
        if ($ostype -ne 'linux') {
            Bad "Docker is set to '$ostype' containers; the session needs Linux containers"
            Note '-> Right-click the Docker Desktop tray icon > Switch to Linux containers.'
            $dockerOk = $false
        }
        if ($mem -gt 0 -and $mem -lt 2000000000) {
            Warn ("Docker has under 2 GB of memory ({0} MB); builds may fail. Docker Desktop > Settings > Resources: give it 4 GB." -f [int]($mem / 1000000))
        }
    }
}

# ---- 2. Compose -------------------------------------------------------------
Say ''
Say '2. Docker Compose'
$compose = $null
if ($dockerOk) {
    if ((Invoke-Native 'docker' @('compose', 'version', '--short')) -eq 0) {
        $compose = @('docker', 'compose')
        Ok ("docker compose works (" + $script:Log.Trim() + ")")
    } elseif ((Get-Command docker-compose -ErrorAction SilentlyContinue) -and (Invoke-Native 'docker-compose' @('version', '--short')) -eq 0) {
        $compose = @('docker-compose')
        Ok ("docker-compose (old standalone version) works: " + $script:Log.Trim())
        Warn "the newer 'docker compose' is not installed; the old one usually works but upgrading Docker is safer"
    } else {
        Bad "neither 'docker compose' nor 'docker-compose' works"
        Note '-> Update Docker Desktop.'
    }
} else { Note 'skipped (Docker not ready)' }

function Invoke-Compose([string[]]$cargs) {
    $all = @()
    if ($compose.Count -gt 1) { $all += $compose[1..($compose.Count - 1)] }
    $all += @('-p', $Project) + $cargs
    return Invoke-Native $compose[0] $all
}

# ---- 3. architecture ---------------------------------------------------------
Say ''
Say "3. Your machine's architecture"
if ($dockerOk) {
    Ok "Docker reports this machine as $darch (confirmed against the containers in step 5)"
    if ($env:DOCKER_DEFAULT_PLATFORM) {
        Warn "DOCKER_DEFAULT_PLATFORM is set to '$($env:DOCKER_DEFAULT_PLATFORM)'; this forces emulation on some machines. Unset it unless you know why it is there."
    }
} else { Note 'skipped (Docker not ready)' }

# ---- 4. port ---------------------------------------------------------------
Say ''
Say "4. Port $Port (the session will need it)"
$portFree = $true
if (Test-PortBusy) {
    $portFree = $false
    Bad "something is already listening on port $Port"
    Note "-> Find it with:  netstat -ano | findstr :$Port      (then stop that program)"
    Note "-> If it is a Docker project you started earlier, run 'docker compose down' in that project's folder."
} else { Ok "port $Port is free" }

# ---- 5. pull / build / run -----------------------------------------------------
Say ''
Say '5. Pull, build and run the hello-world containers'
$pyBuilt = $true
if ($compose) {
    $t0 = Get-Date
    if ((Invoke-Compose @('pull', 'hello-db')) -eq 0) {
        Ok ("download postgres:16-alpine ({0:N0}s)" -f ((Get-Date) - $t0).TotalSeconds)
        $appBuilt = $true
        $t0 = Get-Date
        if ((Invoke-Compose @('build', 'hello-app')) -eq 0) { Ok ("build hello-app  (installs the same OS packages the session needs) ({0:N0}s)" -f ((Get-Date) - $t0).TotalSeconds) }
        else { Bad 'build hello-app  (installs the same OS packages the session needs)'; Explain; $appBuilt = $false }
        $t0 = Get-Date
        if ((Invoke-Compose @('build', 'hello-py')) -eq 0) { Ok ("build hello-py   (installs the same Python packages the session needs) ({0:N0}s)" -f ((Get-Date) - $t0).TotalSeconds) }
        else { Bad 'build hello-py   (installs the same Python packages the session needs)'; Explain; $pyBuilt = $false }
        foreach ($svc in @('hello-db', 'hello-app', 'hello-py')) {
            if ($svc -eq 'hello-app' -and -not $appBuilt) { continue }
            if ($svc -eq 'hello-py' -and -not $pyBuilt) { continue }
            if ((Invoke-Compose @('run', '--rm', $svc)) -eq 0) {
                $a = ''
                foreach ($l in ($script:Log -split "`r?`n")) { if ($l -match '^ARCH=(.+)$') { $a = $Matches[1].Trim() } }
                if ($a -and $a -ne $darch) {
                    Warn "$svc ran as $a but this machine is ${darch}: it is running under emulation (slow, may fail)"
                    Note '-> Docker Desktop > Settings > General: make sure no platform override is set. Tell the organiser.'
                } else { Ok "$svc ran ($a)" }
            } else { Bad "$svc did not run"; Explain }
        }
    } else {
        Bad 'download postgres:16-alpine'
        Explain
        Note 'skipping builds: the base images could not be downloaded'
        $pyBuilt = $false
    }
} else { Note 'skipped (Docker Compose not ready)' }

# ---- 6. publish the port ----------------------------------------------------------
Say ''
Say "6. Can Docker publish port $Port and answer on it?"
if ($compose -and $portFree -and $pyBuilt) {
    if ((Invoke-Compose @('up', '-d', 'hello-port')) -eq 0) {
        $got = ''
        for ($i = 0; $i -lt 15; $i++) {
            $got = Get-HttpLine
            if ($got -like 'HTTP*') { break }
            Start-Sleep -Seconds 1
        }
        if ($got -like 'HTTP*') { Ok "a test web server answered on http://localhost:$Port" }
        else {
            Bad "the test container started but nothing answered on localhost:$Port"
            Note '-> A firewall or security tool may be blocking local ports. Tell the organiser.'
        }
    } else { Bad "Docker could not publish port $Port"; Explain }
} elseif ($compose -and -not $portFree) { Note "skipped (port $Port is already in use, see step 4)" }
elseif ($compose) { Note 'skipped (the hello-py image could not be built, see step 5)' }
else { Note 'skipped (Docker Compose not ready)' }

# ---- clean up ----------------------------------------------------------
if ($compose) { [void](Invoke-Compose @('down', '--remove-orphans')) }

# ---- verdict -----------------------------------------------------------------
Say ''
if ($script:Fails.Count -eq 0) {
    Say '=============================================================' 'Green'
    Say '   YOU ARE READY' 'Green'
    Say '   Everything checked out. Nothing more to do until the session.' 'Green'
    Say '=============================================================' 'Green'
    if ($script:Warns.Count -gt 0) {
        Say ''
        Say ("   Ready, but with {0} warning(s) worth a look:" -f $script:Warns.Count)
        foreach ($w in $script:Warns) { Say "   - $w" }
    }
    Say ''
    Say '   (This left no containers running. The downloaded images and'
    Say '   installed packages stay cached, which makes the real thing'
    Say '   start faster on the day. Run this again if it has been more'
    Say '   than a couple of days - Docker can quietly clear its cache.)'
    $exit = 0
} else {
    Say '=============================================================' 'Red'
    Say ("   NOT READY: {0} problem(s)" -f $script:Fails.Count) 'Red'
    Say '=============================================================' 'Red'
    Say ''
    foreach ($f in $script:Fails) { Say "   - $f" }
    Say ''
    Say '   Fix what it says above and run this again.'
    Say '   Stuck? Send the organiser the file  preflight-report.txt'
    Say '   (it is in this folder and contains everything shown here).'
    $exit = 1
}
Say ''
exit $exit
