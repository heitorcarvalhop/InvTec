<#
InvTec - instalador simplificado (primeira instalacao) - CORPO REAL.

Este arquivo e distribuido junto com "Instalar InvTec.bat" e InvTec.cer
(ver docs/windows-release.md, secao "Instalador simplificado para
usuarios") - os 3 arquivos precisam estar na MESMA pasta. O .bat e so um
launcher minimo (eleva via UAC se necessario, chama este .ps1 com
-File, propaga o codigo de saida) - toda a logica real de verificacao de
certificado/download/instalacao fica AQUI, sem Base64, sem
Invoke-Expression, 100% auditavel abrindo este arquivo normalmente.

Resolve o caminho do InvTec.cer via $PSScriptRoot (preenchido
automaticamente pelo PowerShell com a pasta deste proprio script quando
executado via "-File") - nao assume nenhum caminho fixo, funciona igual
em Downloads/Desktop/pendrive/pasta de rede, desde que os 3 arquivos
estejam juntos.
#>

$ExpectedSubject = 'CN=GETEC'
$ExpectedThumbprint = 'FDB7FF97F58D1804C06ED8F4AC2ECD9F72537036'
$AppInstallerUrl = 'https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates/InvTec.appinstaller'

$CerPath = Join-Path $PSScriptRoot 'InvTec.cer'
$TempAppInstaller = Join-Path $env:TEMP 'InvTec.appinstaller'

function Write-FalhaEtapa {
  param([string]$Etapa, [string]$Mensagem)
  Write-Host ''
  Write-Host ('FALHA em: {0}' -f $Etapa) -ForegroundColor Red
  Write-Host $Mensagem -ForegroundColor Red
  Write-Host ''
  Write-Host 'A instalacao NAO foi concluida. Procure o suporte de TI antes de tentar novamente.' -ForegroundColor Yellow
}

Write-Host '[1/4] Verificando certificado...' -ForegroundColor Cyan

if (-not (Test-Path $CerPath)) {
  Write-FalhaEtapa '1/4 Verificando certificado' ('Arquivo nao encontrado: {0}. O InvTec.cer precisa estar na MESMA pasta do Instalar InvTec.bat.' -f $CerPath)
  exit 1
}

try {
  $cer = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CerPath)
}
catch {
  Write-FalhaEtapa '1/4 Verificando certificado' ('Nao foi possivel ler o certificado: {0}' -f $_.Exception.Message)
  exit 1
}

if ($cer.Subject -ne $ExpectedSubject) {
  Write-FalhaEtapa '1/4 Verificando certificado' ('Subject inesperado: {0} (esperado {1}). ABORTANDO - nao instalar certificado desconhecido.' -f $cer.Subject, $ExpectedSubject)
  exit 1
}

if ($cer.Thumbprint -ne $ExpectedThumbprint) {
  Write-FalhaEtapa '1/4 Verificando certificado' ('Thumbprint inesperado: {0} (esperado {1}). ABORTANDO - nao instalar certificado desconhecido.' -f $cer.Thumbprint, $ExpectedThumbprint)
  exit 1
}

Write-Host ('  Certificado valido: {0} ({1})' -f $cer.Subject, $cer.Thumbprint) -ForegroundColor Green

Write-Host '[2/4] Instalando certificado...' -ForegroundColor Cyan

$jaConfiavel = $false
foreach ($item in Get-ChildItem Cert:\LocalMachine\TrustedPeople) {
  if ($item.Thumbprint -eq $ExpectedThumbprint) {
    $jaConfiavel = $true
  }
}

if ($jaConfiavel) {
  Write-Host '  Certificado ja instalado e confiavel. Nada a fazer.' -ForegroundColor Yellow
}
else {
  try {
    Import-Certificate -FilePath $CerPath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
    Write-Host '  Certificado instalado com sucesso.' -ForegroundColor Green
  }
  catch {
    Write-FalhaEtapa '2/4 Instalando certificado' $_.Exception.Message
    exit 1
  }
}

Write-Host '[3/4] Baixando InvTec...' -ForegroundColor Cyan

try {
  Invoke-WebRequest -Uri $AppInstallerUrl -OutFile $TempAppInstaller -UseBasicParsing
}
catch {
  Write-FalhaEtapa '3/4 Baixando InvTec' $_.Exception.Message
  exit 1
}

Write-Host ('  Baixado em: {0}' -f $TempAppInstaller) -ForegroundColor Green

Write-Host '[4/4] Instalando InvTec...' -ForegroundColor Cyan

try {
  Add-AppxPackage -AppInstallerFile $TempAppInstaller
}
catch {
  Write-FalhaEtapa '4/4 Instalando InvTec' $_.Exception.Message
  exit 1
}

Remove-Item $TempAppInstaller -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '=================================' -ForegroundColor Green
Write-Host 'InvTec instalado com sucesso!' -ForegroundColor Green
Write-Host '=================================' -ForegroundColor Green
Write-Host ''
Write-Host 'Voce ja pode abrir o InvTec pelo Menu Iniciar.'
exit 0
