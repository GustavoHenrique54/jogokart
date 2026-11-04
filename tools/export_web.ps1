param(
    [switch]$InstallTemplates
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $ProjectDir "build\web"

$GodotConsole = Get-ChildItem "$env:USERPROFILE\OneDrive*\Godot_v4.7*_console.exe" -Recurse -File -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $GodotConsole) {
    Write-Error "Executavel console do Godot 4.7 nao encontrado."
}

$TemplateDir = "$env:APPDATA\Godot\export_templates\4.7.2.stable"
$WebTemplate = Join-Path $TemplateDir "web_nothreads_release.zip"

if (-not (Test-Path $WebTemplate)) {
    if ($InstallTemplates) {
        Write-Host "Baixando Export Templates oficiais do Godot 4.7.2..." -ForegroundColor Cyan
        $TpzPath = Join-Path $env:TEMP "Godot_v4.7.2-stable_export_templates.tpz"
        $Url = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
        Invoke-WebRequest -Uri $Url -OutFile $TpzPath
        New-Item -ItemType Directory -Force -Path $TemplateDir | Out-Null
        Expand-Archive -Path $TpzPath -DestinationPath $env:TEMP -Force
        Move-Item -Path "$env:TEMP\templates\*" -Destination $TemplateDir -Force
        Remove-Item $TpzPath -Force
    } else {
        Write-Host "Export Templates do Godot 4.7.2 ainda nao estao instalados." -ForegroundColor Yellow
        Write-Host "Para instalar automaticamente os templates Web e gerar o build, rode:" -ForegroundColor Cyan
        Write-Host "  powershell -ExecutionPolicy Bypass -File tools\export_web.ps1 -InstallTemplates"
        Write-Host "Ou no Editor do Godot: Editor -> Manage Export Templates -> Download and Install."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
& $GodotConsole --headless --path $ProjectDir --export-release "Web" "$OutDir\index.html"
Write-Host "Build Web exportado com sucesso em: $OutDir" -ForegroundColor Green

