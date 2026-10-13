<#
.SYNOPSIS
  Gera dist/windows/InvTec.appinstaller para a versao atual do InvTec.

.DESCRIPTION
  Roda DEPOIS de build_installer.ps1 (precisa do .msix ja gerado). O
  arquivo .appinstaller resultante e o que fica hospedado numa URL HTTPS
  ESTAVEL (ver docs/windows-release.md, secao "Hospedagem") - o mesmo
  endereco, sobrescrito a cada release; e ele que o Windows consulta
  para detectar/oferecer atualizacao.

.PARAMETER Version
  Versao de 3 partes (ex.: 1.0.0) usada no NOME do arquivo .msix
  (InvTec-1.0.0.msix - convencao do bucket invtec-updates). Se omitida,
  e derivada de pubspec.yaml (major.minor.patch).

  O atributo Version="..." dentro do XML (topo e MainPackage) usa 4
  partes (major.minor.patch.0) - essa e a Version REAL dentro do
  AppxManifest do pacote, que o pacote `msix` sempre gera terminando em
  ".0" (ignora o build number "+N" do pubspec de proposito). As duas
  SEMPRE derivam do mesmo pubspec.yaml, entao sempre batem automaticamente
  com o .msix real gerado por build_installer.ps1.

.PARAMETER BaseUrl
  URL HTTPS estavel onde este .appinstaller e os .msix versionados vao
  ficar hospedados (sem barra final), ex.:
  "https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates".
  Pode vir tambem da variavel de ambiente INVTEC_UPDATE_BASE_URL. Se
  nenhum dos dois for definido, usa um placeholder obvio - o arquivo e
  gerado (nao bloqueia o trabalho), mas NAO pode ser publicado assim.
#>
param(
  [string]$Version,
  [string]$BaseUrl = $(if ($env:INVTEC_UPDATE_BASE_URL) { $env:INVTEC_UPDATE_BASE_URL } else { 'https://REPLACE_ME.example.com/invtec' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$BaseUrl = $BaseUrl.TrimEnd('/')

$pubspecContent = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw

if (-not $Version) {
  if ($pubspecContent -notmatch 'version:\s*(\d+\.\d+\.\d+)(\+\d+)?') {
    throw "Nao foi possivel ler 'version:' em pubspec.yaml"
  }
  $Version = $Matches[1]
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
  throw "-Version precisa ter 3 partes (major.minor.patch), ex. '1.0.0'. Recebido: '$Version'"
}
$shortVersion = $Version
$fullVersion = "$shortVersion.0"

$distDir = Join-Path $repoRoot 'dist\windows'
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$msixFileName = "InvTec-$shortVersion.msix"
$msixPath = Join-Path $distDir $msixFileName
if (-not (Test-Path $msixPath)) {
  Write-Warning "Nao encontrei $msixPath - rode build_installer.ps1 primeiro (ou confirme a versao com -Version)."
}

# Identidade e Publisher precisam bater EXATAMENTE com msix_config em
# pubspec.yaml e com o Subject do certificado - ver docs/windows-release.md.
# Lidos diretamente de pubspec.yaml (em vez de hardcoded aqui) para que
# pubspec.yaml continue sendo a UNICA fonte de verdade - evita o risco de
# alguem mudar msix_config e esquecer de atualizar este script, o que
# geraria um .appinstaller com Name/Publisher divergente do .msix real e
# faria o App Installer recusar a instalacao/atualizacao.
if ($pubspecContent -notmatch 'identity_name:\s*(\S+)') {
  throw "Nao foi possivel ler 'identity_name:' em msix_config (pubspec.yaml)"
}
$packageName = $Matches[1]
if ($pubspecContent -notmatch 'publisher:\s*(.+)') {
  throw "Nao foi possivel ler 'publisher:' em msix_config (pubspec.yaml)"
}
$publisher = $Matches[1].Trim()

$appInstallerPath = Join-Path $distDir 'InvTec.appinstaller'

$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
  Uri="$BaseUrl/InvTec.appinstaller"
  Version="$fullVersion"
  xmlns="http://schemas.microsoft.com/appx/appinstaller/2021">
  <MainPackage
    Name="$packageName"
    Publisher="$publisher"
    Version="$fullVersion"
    ProcessorArchitecture="x64"
    Uri="$BaseUrl/$msixFileName" />
  <UpdateSettings>
    <OnLaunch
      HoursBetweenUpdateChecks="0"
      ShowPrompt="true"
      UpdateBlocksActivation="false" />
  </UpdateSettings>
</AppInstaller>
"@

Set-Content -Path $appInstallerPath -Value $xml -Encoding utf8

Write-Host "Gerado: $appInstallerPath" -ForegroundColor Green
Write-Host "  Uri (estavel, publicar sempre no mesmo endereco): $BaseUrl/InvTec.appinstaller"
Write-Host "  MainPackage.Uri (versionado): $BaseUrl/$msixFileName"
Write-Host "  Version (XML, bate com a Identity real do .msix): $fullVersion"

if ($BaseUrl -eq 'https://REPLACE_ME.example.com/invtec') {
  Write-Warning "BaseUrl ainda e um placeholder - defina INVTEC_UPDATE_BASE_URL ou passe -BaseUrl com o endereco real antes de publicar este arquivo."
}
