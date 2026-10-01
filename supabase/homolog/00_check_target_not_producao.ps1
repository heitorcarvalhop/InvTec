<#
.SYNOPSIS
PROMPT 11.3.4.1 - equivalente PowerShell de 00_check_target_not_producao.sh
(mesma logica, para quem nao tem Git Bash disponivel/no PATH no Windows).

Guarda de seguranca obrigatoria ANTES de rodar qualquer script de
supabase/homolog/, E antes de colar qualquer SQL no SQL Editor. Nenhum
outro script desta pasta deve ser rodado sem que este aqui imprima
"LIBERADO" primeiro.

LIMITACAO IMPORTANTE (secao 3 do PROMPT 11.3.4.1): este script so compara
ARQUIVOS DE CONFIGURACAO (env/*.env vs. o .env de producao deste
repositorio). Ele NAO sabe, e NAO PODE saber, qual projeto esta realmente
aberto na aba do navegador onde voce vai colar o SQL - rodar este script
no terminal NAO protege automaticamente um SQL colado manualmente no SQL
Editor de outro projeto (ex.: uma aba antiga, ainda aberta, do projeto de
producao). Por isso a ULTIMA etapa pede para voce digitar o ref que voce
VE na URL do Dashboard aberto - essa confirmacao manual nao e opcional.

NUNCA imprime a URL nem a chave completas - so uma previa curta do project
ref (4 caracteres + comprimento), suficiente para conferencia visual
humana, insuficiente para ser usado como credencial.

NOTA DE CODIFICACAO: este arquivo usa so caracteres ASCII de proposito
(sem acentos, sem travessao) - o PowerShell 5.1 do Windows le arquivos
.ps1 sem BOM usando o codepage ANSI do sistema, e caracteres UTF-8
multibyte (acentos, travessoes) viravam bytes invalidos que quebravam o
parser. Nao reintroduza acentos/travessoes neste arquivo sem confirmar
que o arquivo tem BOM UTF-8.

.PARAMETER HomologEnvFile
Caminho do arquivo .env de HOMOLOGACAO (ex.: env/homologacao.env - ver
env/homologacao.env.example).

.PARAMETER ProdEnvFile
Caminho do .env de PRODUCAO deste repositorio (padrao: .\.env - o mesmo
arquivo que flutter run/flutter build usam quando nenhuma flag
--dart-define-from-file e passada).

.EXAMPLE
.\00_check_target_not_producao.ps1 -HomologEnvFile env\homologacao.env
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$HomologEnvFile,

    [string]$ProdEnvFile = ".env"
)

function Fail([string]$Motivo) {
    Write-Host "RECUSADO: $Motivo" -ForegroundColor Red
    Write-Host "Nenhum script de homologacao deve prosseguir, e nenhum SQL deve ser colado." -ForegroundColor Red
    exit 1
}

function Get-SupabaseRef([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $conteudo = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $conteudo) { return $null }
    $m = [regex]::Match($conteudo, 'SUPABASE_URL=https://([a-z0-9]+)\.supabase\.co')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    return $null
}

function Get-SupabaseEnvLabel([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $conteudo = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $conteudo) { return $null }
    $m = [regex]::Match($conteudo, '(?m)^SUPABASE_ENV=([a-zA-Z]*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim().ToLowerInvariant() }
    return $null
}

if (-not (Test-Path $HomologEnvFile)) { Fail "arquivo '$HomologEnvFile' nao encontrado." }
if (-not (Test-Path $ProdEnvFile)) { Fail "arquivo de producao '$ProdEnvFile' nao encontrado - sem ele nao da para confirmar que o destino e diferente." }

$declarado = Get-SupabaseEnvLabel -Path $HomologEnvFile
if ($declarado -ne "homologacao") {
    $mostrado = if ([string]::IsNullOrEmpty($declarado)) { "<ausente>" } else { $declarado }
    Fail "'$HomologEnvFile' nao declara SUPABASE_ENV=homologacao explicitamente (encontrado: '$mostrado'). O nome do arquivo nunca e suficiente."
}

$refProd = Get-SupabaseRef -Path $ProdEnvFile
$refHomolog = Get-SupabaseRef -Path $HomologEnvFile

if ([string]::IsNullOrEmpty($refProd)) { Fail "nao foi possivel extrair o project ref de producao de '$ProdEnvFile' - recusando por seguranca (destino nao identificavel)." }
if ([string]::IsNullOrEmpty($refHomolog)) { Fail "nao foi possivel extrair o project ref de '$HomologEnvFile' - recusando por seguranca (destino nao identificavel)." }
if ($refHomolog -eq $refProd) { Fail "o project ref de '$HomologEnvFile' e IGUAL ao de producao - isto apontaria para o banco de PRODUCAO." }

# Previas pre-calculadas em variaveis simples - evita subexpressoes $()
# aninhadas dentro de strings interpoladas.
$refHomologPreview = $refHomolog.Substring(0, 4)
$refHomologLen = $refHomolog.Length
$refProdPreview = $refProd.Substring(0, 4)
$refProdLen = $refProd.Length

Write-Host "OK (arquivos) - '$HomologEnvFile' e diferente do projeto de producao."
Write-Host "  SUPABASE_ENV declarado: $declarado"
Write-Host "  project ref (homologacao): $refHomologPreview... ($refHomologLen caracteres)"
Write-Host "  project ref (producao, so para conferencia visual): $refProdPreview... ($refProdLen caracteres)"
Write-Host "  (nenhuma URL ou chave completa foi impressa)"
Write-Host ""
Write-Host "CONFIRMACAO VISUAL OBRIGATORIA - este script nao ve sua tela."
Write-Host "No navegador, confira a URL do Dashboard do projeto que esta ABERTO"
Write-Host "agora (formato: https://supabase.com/dashboard/project/<ref>)."
$refDashboard = Read-Host "Digite o <ref> que voce VE na URL do Dashboard aberto"
$refDashboard = ($refDashboard -replace '\s', '').ToLowerInvariant()

if ([string]::IsNullOrEmpty($refDashboard)) { Fail "nenhum ref foi digitado - sem confirmacao visual, nao prossiga." }
if ($refDashboard -eq $refProd) { Fail "o ref digitado e o de PRODUCAO - a aba aberta no navegador NAO e homologacao. Feche-a e abra o projeto de homologacao antes de continuar." }
if ($refDashboard -ne $refHomolog) {
    $refDashboardPreviewLen = [Math]::Min(4, $refDashboard.Length)
    $refDashboardPreview = $refDashboard.Substring(0, $refDashboardPreviewLen)
    Fail "o ref digitado ('$refDashboardPreview...') nao bate com o ref de '$HomologEnvFile' ('$refHomologPreview...'). Nao e o projeto esperado - nao prossiga com ambiguidade."
}

Write-Host ""
Write-Host "LIBERADO - arquivo de configuracao E aba do Dashboard confirmam o mesmo projeto de HOMOLOGACAO." -ForegroundColor Green
