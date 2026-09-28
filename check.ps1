# Lint + type-check the whole game:  right-click > Run with PowerShell, or `.\check.ps1`
Set-Location $PSScriptRoot
$bin = "$env:USERPROFILE\.rokit\bin"
& "$bin\rojo.exe" sourcemap default.project.json --output sourcemap.json | Out-Null
if (-not (Test-Path globalTypes.d.luau)) {
	Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau" -OutFile globalTypes.d.luau
}
Write-Host "== selene (lint) ==" -ForegroundColor Cyan
& "$bin\selene.exe" src 2>&1 | Select-Object -Last 3
Write-Host "== luau-lsp (types): errors only ==" -ForegroundColor Cyan
& "$bin\luau-lsp.exe" analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json --ignore="**/LowPolyData/**" src 2>&1 |
	Where-Object { $_ -match "TypeError|SyntaxError|UnknownGlobal" } | ForEach-Object { ($_ -replace '^.*src[\/]', '').Trim() }
