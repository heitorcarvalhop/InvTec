<#
.SYNOPSIS
  Preflight: confirma que InvTec.appinstaller e o .msix publicados num
  host HTTPS estao realmente acessiveis e com headers corretos antes de
  considerar esse host apto para atualizacao automatica.

.DESCRIPTION
  Nao instala nada, nao baixa o arquivo inteiro (usa HEAD, com fallback
  para Range request se o host nao suportar HEAD). Para cada um dos 2
  arquivos, exige:
    - acessivel via HTTPS (status 200 ou 206, apos seguir redirecionamentos)
    - header Content-Length presente e > 0
    - header Content-Type EXATAMENTE application/appinstaller (para o
      .appinstaller) ou application/msix (para o .msix) - comparando so
      o media-type, ignorando parametros tipo ";charset=..." se vierem.

  Falha claramente (exit code 1) se qualquer requisito nao for atendido
  em qualquer um dos 2 arquivos. Nao tenta nenhuma gambiarra (sem
  reescrever headers, sem proxy, sem truque de nome de arquivo) - so
  reporta.

.PARAMETER BaseUrl
  URL base estavel onde os artefatos estao publicados (sem barra final).
  Se omitida, usa a variavel de ambiente INVTEC_UPDATE_BASE_URL.

.PARAMETER Version
  Versao de 3 partes do .msix a verificar (ex.: 1.0.0 -> InvTec-1.0.0.msix).
  Se omitida, e derivada de pubspec.yaml (major.minor.patch).
#>
param(
  [string]$BaseUrl = $env:INVTEC_UPDATE_BASE_URL,
  [string]$Version
)

$ErrorActionPreference = 'Stop'

if (-not $BaseUrl) {
  throw "BaseUrl nao informado. Passe -BaseUrl ou defina a variavel de ambiente INVTEC_UPDATE_BASE_URL."
}
$BaseUrl = $BaseUrl.TrimEnd('/')

if (-not $Version) {
  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
  $pubspecContent = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
  if ($pubspecContent -notmatch 'version:\s*(\d+\.\d+\.\d+)(\+\d+)?') {
    throw "Nao foi possivel ler 'version:' em pubspec.yaml"
  }
  $Version = $Matches[1]
}

function Test-ReleaseArtifact {
  param(
    [string]$Url,
    [string]$ExpectedContentType
  )

  $resultado = [ordered]@{
    Url                   = $Url
    Acessivel             = $false
    StatusCode            = $null
    ContentLength         = $null
    ContentType           = $null
    ContentTypeCompativel = $false
    Erro                  = $null
  }

  try {
    $resp = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -MaximumRedirection 5
  }
  catch [System.Net.WebException] {
    # Alguns hosts (ex.: redirecionamentos para blob storage) as vezes
    # recusam HEAD mesmo aceitando GET normalmente. Fallback: GET com
    # Range pedindo so o primeiro byte, pra nao baixar o arquivo inteiro
    # so pra inspecionar headers.
    try {
      $resp = Invoke-WebRequest -Uri $Url -Method Get -Headers @{ Range = 'bytes=0-0' } -UseBasicParsing -MaximumRedirection 5
    }
    catch {
      $resultado.Erro = $_.Exception.Message
      return [pscustomobject]$resultado
    }
  }
  catch {
    $resultado.Erro = $_.Exception.Message
    return [pscustomobject]$resultado
  }

  $resultado.StatusCode = [int]$resp.StatusCode
  $resultado.Acessivel = ($resultado.StatusCode -eq 200 -or $resultado.StatusCode -eq 206)

  $contentLength = $resp.Headers['Content-Length']
  if ($contentLength) {
    $resultado.ContentLength = [int64]($contentLength | Select-Object -First 1)
  }

  $contentType = $resp.Headers['Content-Type']
  if ($contentType) {
    $resultado.ContentType = ($contentType | Select-Object -First 1)
    # Compara so o media-type (antes de ';'), caso o header venha com
    # parametro extra (ex. "application/msix; charset=utf-8").
    $mediaType = ($resultado.ContentType -split ';')[0].Trim().ToLowerInvariant()
    $resultado.ContentTypeCompativel = ($mediaType -eq $ExpectedContentType.ToLowerInvariant())
  }

  return [pscustomobject]$resultado
}

$msixFileName = "InvTec-$Version.msix"

$alvos = @(
  @{ Nome = 'InvTec.appinstaller'; Url = "$BaseUrl/InvTec.appinstaller"; EsperadoContentType = 'application/appinstaller' }
  @{ Nome = $msixFileName; Url = "$BaseUrl/$msixFileName"; EsperadoContentType = 'application/msix' }
)

$tudoOk = $true

foreach ($alvo in $alvos) {
  Write-Host "Verificando $($alvo.Nome) ..." -ForegroundColor Cyan
  $r = Test-ReleaseArtifact -Url $alvo.Url -ExpectedContentType $alvo.EsperadoContentType

  if ($r.Erro) {
    Write-Host "  INACESSIVEL: $($r.Erro)" -ForegroundColor Red
    $tudoOk = $false
  }
  else {
    Write-Host "  Status:          $($r.StatusCode) $(if ($r.Acessivel) { '(OK)' } else { '(FALHOU)' })"
    Write-Host "  Content-Length:  $(if ($r.ContentLength) { $r.ContentLength } else { 'AUSENTE' })"
    Write-Host "  Content-Type:    $(if ($r.ContentType) { $r.ContentType } else { 'AUSENTE' }) (esperado: $($alvo.EsperadoContentType))"
    if (-not $r.Acessivel) { $tudoOk = $false }
    if (-not $r.ContentLength) { $tudoOk = $false }
    if (-not $r.ContentTypeCompativel) {
      Write-Host "  FALHA: Content-Type incompativel com '$($alvo.EsperadoContentType)'." -ForegroundColor Red
      $tudoOk = $false
    }
  }
  Write-Host ''
}

if ($tudoOk) {
  Write-Host "Preflight OK: todos os artefatos estao acessiveis, com Content-Length e Content-Type corretos." -ForegroundColor Green
  Write-Host "Host '$BaseUrl' esta apto para atualizacao automatica."
}
else {
  Write-Host "PREFLIGHT FALHOU em pelo menos um requisito." -ForegroundColor Red
  Write-Host "NAO considerar '$BaseUrl' apto ainda. Nao tente corrigir isso com gambiarra" -ForegroundColor Yellow
  Write-Host "(reescrever headers, proxy, truque de nome de arquivo). Se o Content-Type" -ForegroundColor Yellow
  Write-Host "nao puder ser configurado corretamente neste host, use outro host HTTPS com" -ForegroundColor Yellow
  Write-Host "MIME configuravel por arquivo e aponte INVTEC_UPDATE_BASE_URL para ele." -ForegroundColor Yellow
  exit 1
}
