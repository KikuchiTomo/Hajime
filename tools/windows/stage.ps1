param(
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$rust = Join-Path $root 'apps\windows\target'
$swift = Join-Path $root 'core\.build\release'

New-Item -ItemType Directory -Force -Path $Output | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Output 'x86') | Out-Null

Copy-Item (Join-Path $rust 'release\s90_tsf.dll') $Output
Copy-Item (Join-Path $rust 'release\s90-candidate-ui.exe') $Output
Copy-Item (Join-Path $rust 'release\s90-settings.exe') $Output
Copy-Item (Join-Path $rust 'i686-pc-windows-msvc\release\s90_tsf.dll') (Join-Path $Output 'x86')

Copy-Item (Join-Path $swift 's90-engine-host.exe') $Output
Get-ChildItem -Path $swift -Filter '*.dll' | Copy-Item -Destination $Output
Get-ChildItem -Path $swift -Directory -Filter '*.resources' | Copy-Item -Destination $Output -Recurse

$runtime = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Swift\Runtimes') -Directory | Sort-Object Name | Select-Object -Last 1
if (-not $runtime) { throw 'Swift のランタイムが見つかりません' }
Get-ChildItem -Path (Join-Path $runtime.FullName 'usr\bin') -Filter '*.dll' | Copy-Item -Destination $Output

Copy-Item (Join-Path $root 'data\postal\postal-codes.tsv') $Output
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $Output 'LICENSE.txt')
Copy-Item (Join-Path $root 'THIRD_PARTY_NOTICES.md') (Join-Path $Output 'THIRD_PARTY_NOTICES.md')

$required = @('s90_tsf.dll', 'x86\s90_tsf.dll', 's90-engine-host.exe', 's90-candidate-ui.exe', 's90-settings.exe', 'postal-codes.tsv')
foreach ($file in $required) {
    if (-not (Test-Path (Join-Path $Output $file))) { throw "$file がありません" }
}
Write-Host "ok: $Output に集めました"
