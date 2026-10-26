param([Parameter(Mandatory = $true)][string]$Dll)

$expected = @('DllCanUnloadNow', 'DllGetClassObject', 'DllRegisterServer', 'DllUnregisterServer')
$output = & llvm-readobj --coff-exports $Dll
if ($LASTEXITCODE -ne 0) { throw "llvm-readobj が失敗しました: $Dll" }
$actual = @($output | Select-String -Pattern '^\s*Name:\s*(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object)
$difference = Compare-Object -ReferenceObject $expected -DifferenceObject $actual
if ($difference) {
    Write-Host "公開する関数が決まりと違います: $($actual -join ', ')"
    exit 1
}
Write-Host "ok: $Dll が公開する関数は $($expected -join ', ') だけです"
