param(
    [int]$Port = 8080,
    [switch]$Headless
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$ToolsDir = $PSScriptRoot

# 1. Localiza o executavel do Godot 4.7
$GodotExe = (Get-ChildItem "$env:USERPROFILE\OneDrive*\Godot_v4.7*_win64_console.exe" -Recurse | Select-Object -First 1).FullName

if (-not $GodotExe) {
    $GodotExe = (Get-Command godot -ErrorAction SilentlyContinue).Source
}

if (-not $GodotExe) {
    Write-Error "Nao encontrei o executavel do Godot 4.7 automaticamente. Abra o projeto no Godot e clique em 'Hospedar partida' enquanto roda este script para o tunel."
}

# 2. Garante o cloudflared para criar um tunel WSS gratuito (sem precisar abrir porta no roteador)
$Cloudflared = Join-Path $ToolsDir "cloudflared.exe"
if (-not (Test-Path $Cloudflared)) {
    Write-Host "[1/2] Baixando cloudflared (tunel gratuito Cloudflare)..." -ForegroundColor Cyan
    $Url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    Invoke-WebRequest -Uri $Url -OutFile $Cloudflared
}

# 3. Se pedido (-Headless), sobe um servidor dedicado em segundo plano
$ServerProc = $null
if ($Headless -and $GodotExe) {
    Write-Host "[2/2] Iniciando servidor dedicado Godot na porta $Port..." -ForegroundColor Green
    $ServerProc = Start-Process -FilePath $GodotExe -ArgumentList "--headless","--path",$ProjectDir,"--","--server","--port=$Port" -PassThru -NoNewWindow
} else {
    Write-Host "[2/2] No jogo, clique em 'Hospedar partida (porta $Port)'." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Abrindo tunel seguro WSS (copie a URL https://xxxx.trycloudflare.com que aparecer abaixo e mande para seu colega!):" -ForegroundColor Cyan
Write-Host "Pressione Ctrl+C para encerrar." -ForegroundColor DarkGray
Write-Host ""

try {
    & $Cloudflared tunnel --url "http://localhost:$Port"
} finally {
    if ($ServerProc -and -not $ServerProc.HasExited) {
        Stop-Process -Id $ServerProc.Id -Force
    }
}

