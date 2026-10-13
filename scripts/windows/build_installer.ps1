<#
.SYNOPSIS
  Build do InvTec para Windows + geracao do instalador MSIX.

.DESCRIPTION
  1. flutter pub get
  2. flutter analyze
  3. flutter test (so se -RunTests)
  4. flutter build windows --release
  5. dart run msix:create (assinado, se o certificado existir)
  6. Copia o .msix gerado para um nome versionado em dist/windows/,
     sem sobrescrever releases anteriores.

  Ver docs/windows-release.md para o processo completo (inclui o passo
  seguinte, generate_appinstaller.ps1).

.PARAMETER RunTests
  Se presente, roda `flutter test` entre o analyze e o build. Desligado
  por padrao para builds rapidos de iteracao local; sempre usar antes de
  publicar uma release real.

.PARAMETER CertificatePath
  Caminho do .pfx gerado por create_signing_certificate.ps1. Padrao:
  certs/InvTec.pfx. Se o arquivo nao existir, o MSIX e gerado SEM
  assinatura estavel (certificado de teste do proprio pacote msix) - nao
  serve para distribuicao real, so para inspecionar a estrutura do pacote.

.PARAMETER CertificatePassword
  Senha do certificado, como SecureString. Se omitida e o certificado
  existir, e pedida interativamente.
#>
param(
  [switch]$RunTests,
  [string]$CertificatePath = (Join-Path $PSScriptRoot '..\..\certs\InvTec.pfx'),
  [SecureString]$CertificatePassword
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

function Invoke-Step {
  param([string]$Description, [scriptblock]$Command)
  Write-Host "==> $Description" -ForegroundColor Cyan
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Falhou: $Description (exit code $LASTEXITCODE)"
  }
}

Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'flutter analyze' { flutter analyze }

if ($RunTests) {
  Invoke-Step 'flutter test' { flutter test }
}
else {
  Write-Host 'Testes pulados (use -RunTests para rodar flutter test antes do build). SEMPRE use -RunTests antes de publicar uma release real.' -ForegroundColor Yellow
}

Invoke-Step 'flutter build windows --release' { flutter build windows --release }

$msixArgs = @('run', 'msix:create')

if (Test-Path $CertificatePath) {
  if (-not $CertificatePassword) {
    $CertificatePassword = Read-Host -AsSecureString "Senha do certificado ($CertificatePath)"
  }
  $plainPassword = [System.Net.NetworkCredential]::new('', $CertificatePassword).Password
  $msixArgs += @('--certificate-path', $CertificatePath, '--certificate-password', $plainPassword)
  Write-Host "Assinando com certificado: $CertificatePath" -ForegroundColor Cyan
}
else {
  Write-Warning "Certificado nao encontrado em '$CertificatePath'. O MSIX sera gerado com um certificado de TESTE criado pelo proprio pacote msix - NAO serve para distribuicao real nem para atualizar instalacoes existentes. Gere o certificado estavel com scripts\windows\create_signing_certificate.ps1 antes de publicar."
}

Invoke-Step 'dart run msix:create' { dart @msixArgs }

# output_name: InvTec em msix_config sempre gera dist/windows/InvTec.msix -
# copiamos para um nome versionado para nao sobrescrever releases
# anteriores (ver docs/windows-release.md, "Pacotes versionados").
#
# Nome do ARQUIVO usa major.minor.patch (3 partes, ex. InvTec-1.0.0.msix -
# convencao do bucket invtec-updates). A Version REAL dentro do pacote
# (Identity/AppxManifest) e sempre major.minor.patch.0 (4 partes) - o
# pacote msix ignora o build number "+N" do pubspec de proposito (ver
# msix-3.18.0/lib/src/configuration.dart, _getPubspecVersion). O nome do
# arquivo nao precisa ter as 4 partes (e so um nome, o Uri do appinstaller
# resolve isso); o que precisa bater exatamente com a Version real e o
# atributo Version="..." dentro do .appinstaller - ver generate_appinstaller.ps1.
$pubspecContent = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspecContent -notmatch 'version:\s*(\d+\.\d+\.\d+)(\+\d+)?') {
  throw "Nao foi possivel ler 'version:' em pubspec.yaml"
}
$shortVersion = $Matches[1]

$distDir = Join-Path $repoRoot 'dist\windows'
$generatedMsix = Join-Path $distDir 'InvTec.msix'
$versionedMsix = Join-Path $distDir "InvTec-$shortVersion.msix"

if (-not (Test-Path $generatedMsix)) {
  throw "MSIX esperado nao encontrado em $generatedMsix"
}
Copy-Item $generatedMsix $versionedMsix -Force

Write-Host ''
Write-Host 'Build concluido.' -ForegroundColor Green
Write-Host "MSIX versionado: $versionedMsix"
Write-Host ''
Write-Host "Proximo passo: scripts\windows\generate_appinstaller.ps1"
