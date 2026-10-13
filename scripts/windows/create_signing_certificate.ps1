<#
.SYNOPSIS
  Gera o certificado de assinatura do InvTec (self-signed), usado para
  assinar o MSIX fora da Microsoft Store.

.DESCRIPTION
  Roda UMA vez (ou raramente - ver docs/windows-release.md, secao
  "Certificado"). O MESMO certificado precisa assinar TODAS as versoes
  futuras do InvTec: gerar um novo a cada release quebra a capacidade do
  Windows de reconhecer upgrades como vindos do mesmo publisher, e o App
  Installer para de oferecer atualizacao automatica para quem ja instalou.

  Gera dois arquivos em certs/ (fora do Git, ver .gitignore):
    - InvTec.pfx  - chave privada + certificado, protegida por senha.
                    NUNCA compartilhar, NUNCA versionar, fazer backup seguro.
    - InvTec.cer  - so a parte publica. E isso que cada maquina precisa
                    instalar/confiar ANTES da primeira instalacao do MSIX
                    (ver docs/windows-release.md, secao "Primeira instalacao").

.PARAMETER Subject
  Subject do certificado. Precisa ser IDENTICO ao campo `publisher` em
  msix_config (pubspec.yaml) - hoje "CN=GETEC". Nao mudar um sem mudar o
  outro.

.PARAMETER ValidYears
  Validade do certificado em anos. Padrao 10 - o suficiente para nao
  precisar regenerar no meio do ciclo de vida do app.

.PARAMETER OutputDir
  Pasta de saida. Padrao certs/ na raiz do repositorio.
#>
param(
  [string]$Subject = 'CN=GETEC',
  [int]$ValidYears = 10,
  [string]$OutputDir = (Join-Path $PSScriptRoot '..\..\certs')
)

$ErrorActionPreference = 'Stop'

# So para diagnostico - nao bloqueia PowerShell 5.1 (ver verificacao do
# PFX mais abaixo, que foi escrita de proposito para funcionar igual nas
# duas versoes, sem depender de qual delas esta rodando).
$psVer = $PSVersionTable.PSVersion
Write-Host "PowerShell detectado: $($psVer.Major).$($psVer.Minor)" -ForegroundColor DarkGray

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$pfxPath = Join-Path $OutputDir 'InvTec.pfx'
$cerPath = Join-Path $OutputDir 'InvTec.cer'

if ((Test-Path $pfxPath) -or (Test-Path $cerPath)) {
  Write-Warning "Ja existe certificado em '$OutputDir'."
  # Mostra o que ja existe SEM pedir a senha do .pfx (GetCertContentType
  # so identifica o formato do arquivo, nao abre o conteudo; o .cer e
  # publico, nao tem senha) - ajuda a decidir se e residuo de uma
  # tentativa anterior ou um certificado definitivo que nao deveria ser
  # sobrescrito.
  if (Test-Path $cerPath) {
    try {
      $existente = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)
      Write-Host "  InvTec.cer atual: Subject=$($existente.Subject) Thumbprint=$($existente.Thumbprint) NotAfter=$($existente.NotAfter)"
    }
    catch {
      Write-Host "  InvTec.cer atual: nao foi possivel ler (' $($_.Exception.Message) ')"
    }
  }
  if (Test-Path $pfxPath) {
    try {
      $tipo = [System.Security.Cryptography.X509Certificates.X509Certificate2]::GetCertContentType($pfxPath)
      Write-Host "  InvTec.pfx atual: formato detectado = $tipo (esperado Pfx) - conteudo NAO foi aberto, senha nao foi pedida"
    }
    catch {
      Write-Host "  InvTec.pfx atual: nao foi possivel identificar o formato ('$($_.Exception.Message)')"
    }
  }
  $resposta = Read-Host 'Sobrescrever e gerar um certificado NOVO? Isso invalida a cadeia de confianca ja instalada em outras maquinas e pode impedir atualizacoes das instalacoes existentes ate reinstalarem do zero. Digite SIM para continuar'
  if ($resposta -ne 'SIM') {
    Write-Host 'Cancelado. Nenhum arquivo foi alterado.'
    exit 0
  }
}

Write-Host "Gerando certificado de assinatura InvTec - Subject: $Subject" -ForegroundColor Cyan

$cert = New-SelfSignedCertificate `
  -Type Custom `
  -Subject $Subject `
  -KeyUsage DigitalSignature `
  -FriendlyName 'InvTec - Assinatura de codigo (MSIX)' `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') `
  -KeyAlgorithm RSA `
  -KeyLength 2048 `
  -KeyExportPolicy Exportable `
  -HashAlgorithm SHA256 `
  -NotAfter (Get-Date).AddYears($ValidYears)

if ($cert.Subject -ne $Subject) {
  throw "Subject gerado ('$($cert.Subject)') nao bate com o esperado ('$Subject') - cancelando antes de exportar."
}

$senha = Read-Host -AsSecureString 'Defina uma senha para proteger o InvTec.pfx (guarde-a - sem ela o .pfx e inutil)'

Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $senha | Out-Null
Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null

# Remove a copia que New-SelfSignedCertificate deixou no CurrentUser\My -
# o .pfx exportado ja e a fonte de verdade; manter duas copias (uma no
# arquivo, outra solta no cert store) so aumenta a chance de confusao
# sobre qual e a "oficial" quando chegar a hora de assinar um release.
Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force

# Confirma, a partir dos arquivos exportados (nao do objeto $cert em
# memoria), que o que foi gravado em disco atende ao checklist: subject
# exato, EKU de code signing, chave privada exportavel no .pfx, validade.
#
# NAO usa "Get-PfxCertificate -Password": esse parametro so existe a
# partir do PowerShell 6.1 (Microsoft.PowerShell.Security) - no Windows
# PowerShell 5.1 ele nao existe e o cmdlet falha com "Nao e possivel
# localizar um parametro que coincida com o nome do parametro 'Password'".
# Em vez disso, instancia X509Certificate2 diretamente com o construtor
# (caminho, SecureString) - esse construtor e nativo do .NET
# Framework/.NET desde sempre, funciona identico no Windows PowerShell
# 5.1 e no PowerShell 7+, sem exigir nenhum modulo/versao especifica, e
# mantem a senha como SecureString o tempo todo (nunca convertida para
# texto plano).
$verifPfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, $senha)
$verifCer = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)

$temEkuCodeSigning = $verifPfx.Extensions |
  Where-Object { $_.Oid.Value -eq '2.5.29.37' } |
  ForEach-Object { $_.EnhancedKeyUsages.Value -contains '1.3.6.1.5.5.7.3.3' }

# Nao inspeciona CspKeyContainerInfo/Exportable aqui de proposito: para
# chaves CNG modernas essa propriedade e' instavel/pode lancar exception
# via a API legada (.PrivateKey) dependendo da versao do .NET. A prova
# real de exportabilidade e mais direta: pedimos -KeyExportPolicy
# Exportable na criacao, e o proprio Export-PfxCertificate acima so
# chega aqui (sem lancar erro) se a chave privada realmente pode ser
# exportada - "HasPrivateKey" so confirma que o .pfx contem a chave.
Write-Host ''
Write-Host 'Verificacao pos-geracao:' -ForegroundColor Cyan
Write-Host "  Subject (.pfx):            $($verifPfx.Subject)"
Write-Host "  Subject (.cer):            $($verifCer.Subject)"
Write-Host "  EKU Code Signing presente: $([bool]$temEkuCodeSigning)"
Write-Host "  Chave privada presente:    $($verifPfx.HasPrivateKey)"
Write-Host "  Valido de:                 $($verifPfx.NotBefore)"
Write-Host "  Valido ate:                $($verifPfx.NotAfter)"

if ($verifPfx.Subject -ne $Subject -or $verifCer.Subject -ne $Subject) {
  throw "Subject exportado nao bate com '$Subject' - NAO use estes arquivos. Apague $pfxPath e $cerPath e rode o script de novo."
}
if (-not $temEkuCodeSigning) {
  throw "Certificado exportado NAO tem o EKU de Code Signing - NAO use estes arquivos para assinar o MSIX."
}
if (-not $verifPfx.HasPrivateKey) {
  throw "O .pfx exportado nao contem a chave privada - inutil para assinatura. Rode o script de novo."
}

Write-Host ''
Write-Host 'Certificado gerado e verificado com sucesso:' -ForegroundColor Green
Write-Host "  Privado (NUNCA compartilhar): $pfxPath"
Write-Host "  Publico (distribuir/instalar nas maquinas antes da 1a instalacao): $cerPath"
Write-Host ''
Write-Host 'IMPORTANTE:' -ForegroundColor Yellow
Write-Host '  - Faca backup do .pfx e da senha em um local seguro (ex.: cofre de senhas da equipe).'
Write-Host '  - Se este certificado for perdido, releases futuros nao poderao mais atualizar'
Write-Host '    instalacoes existentes assinadas por ele - exigiria desinstalar e reinstalar'
Write-Host '    manualmente em cada maquina com um novo certificado/publisher.'
Write-Host '  - Nunca rode este script de novo "porque sim" - so se o certificado atual expirar'
Write-Host '    ou for comprometido.'
