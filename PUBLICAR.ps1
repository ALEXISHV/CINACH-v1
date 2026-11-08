$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!(Test-Path 'appsettings.Production.json')) {
    throw 'Crea appsettings.Production.json usando el archivo de ejemplo y tu conexion de Somee. Consulta LEEME.md.'
}
$config = Get-Content 'appsettings.Production.json' -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($config.ConnectionStrings.Cinach) -or $config.ConnectionStrings.Cinach -match 'TU_SERVIDOR|TU_PASSWORD') {
    throw 'Completa la conexion de Somee en appsettings.Production.json antes de publicar.'
}
dotnet publish CINACH.csproj -c Release -o publish
if ($LASTEXITCODE -ne 0) { throw 'La compilacion fallo. No subas archivos hasta corregir el error mostrado.' }
Copy-Item 'appsettings.Production.json' 'publish/appsettings.Production.json' -Force
Write-Host 'Listo. Sube el CONTENIDO de publish a Somee. No subas el codigo fuente, sql ni las carpetas bin/obj.' -ForegroundColor Green
