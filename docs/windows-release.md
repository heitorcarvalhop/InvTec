# InvTec — Release Windows (MSIX + atualização automática)

Guia curto para publicar/atualizar o InvTec no Windows via MSIX + App
Installer. Sem Microsoft Store, sem atualizador artesanal — só os
mecanismos nativos do Windows.

## Visão geral do fluxo

```
pubspec.yaml (version: X.Y.Z+N)
  -> scripts/windows/build_installer.ps1        (build + assina o MSIX)
  -> scripts/windows/generate_appinstaller.ps1  (gera InvTec.appinstaller)
  -> GitHub Release (opcional, backup/distribuição secundária)
  -> upload MANUAL para o Supabase Storage (bucket invtec-updates) — host oficial do App Installer
  -> scripts/windows/verify_release_artifacts.ps1  (preflight: acessível + Content-Length + Content-Type corretos)
  -> usuário abre o InvTec instalado -> Windows consulta o Supabase Storage -> detecta versão nova -> oferece update
```

O Supabase Storage aqui é **só host de arquivos binários estáticos**
(MSIX/AppInstaller) — não participa de migrations, não roda SQL, não
tem relação com o Postgres de negócio do InvTec nem com Auth/RLS das
tabelas do app. É o mesmo projeto Supabase já usado pelo InvTec, só um
bucket novo e isolado para isso.

## Fonte única de versão

`pubspec.yaml` → `version: X.Y.Z+N`. SemVer no produto:

- **PATCH** (1.0.0 → 1.0.1): correção.
- **MINOR** (1.0.x → 1.1.0): funcionalidade nova compatível.
- **MAJOR** (1.x.x → 2.0.0): mudança grande/incompatível.

**Importante:** o pacote `msix` gera a versão do MSIX como
`major.minor.patch.0` — ele **ignora** o build number (`+N`) de propósito.
Por isso: **toda release Windows precisa incrementar pelo menos o PATCH**
em relação à release Windows anterior. Nunca publicar duas releases
Windows diferentes com o mesmo `major.minor.patch` — o App Installer veria
a mesma versão e não ofereceria atualização nenhuma.

## Identidade do pacote (NÃO mudar depois da 1ª distribuição)

| Campo | Valor |
|---|---|
| `display_name` | InvTec |
| `publisher_display_name` | GETEC |
| `identity_name` | GETEC.InvTec |
| `publisher` | CN=GETEC (precisa bater exatamente com o Subject do certificado) |

Configurado em `pubspec.yaml` → `msix_config`. Se um dia precisar trocar
`publisher`/`identity_name`, toda instalação existente vai precisar ser
desinstalada e reinstalada do zero (não é um "update" — é um app
diferente aos olhos do Windows).

## Certificado de assinatura

MSIX fora da Store precisa ser assinado. Primeira vez (ou se o
certificado expirar/for comprometido):

```powershell
scripts\windows\create_signing_certificate.ps1
```

Gera `certs/InvTec.pfx` (privado, com senha) e `certs/InvTec.cer`
(público). **Nenhum dos dois é versionado** (`.gitignore` já bloqueia
`*.pfx`, `*.cer` e `/certs/`).

- `InvTec.pfx` + senha: backup seguro (cofre de senhas da equipe). Se
  perder, releases futuros não conseguem mais atualizar instalações já
  feitas com o certificado antigo.
- `InvTec.cer`: distribuir para cada máquina que vai instalar o InvTec
  (ver "Primeira instalação" abaixo). Não é segredo — é só a chave
  pública.
- **O mesmo certificado assina todas as versões.** Não gerar um novo a
  cada release.

## Build local + MSIX

```powershell
scripts\windows\build_installer.ps1 [-RunTests] [-CertificatePath <pfx>] [-CertificatePassword <SecureString>]
```

Roda `pub get` → `analyze` → (`test`, se `-RunTests`) → `build windows
--release` → `dart run msix:create`, e deixa o resultado versionado em
`dist/windows/InvTec-X.Y.Z.msix` (3 partes, ex. `InvTec-1.0.0.msix` —
convenção do bucket `invtec-updates`; sem sobrescrever releases
anteriores). Sem certificado em `certs/InvTec.pfx`, gera um MSIX assinado
com certificado de TESTE do próprio pacote `msix` — serve só para
inspecionar a estrutura do pacote, nunca para distribuir.

## Gerar o InvTec.appinstaller

```powershell
scripts\windows\generate_appinstaller.ps1 -BaseUrl "https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates"
```

(ou defina a variável de ambiente `INVTEC_UPDATE_BASE_URL` antes de
rodar). Produz `dist/windows/InvTec.appinstaller` apontando para o `.msix`
versionado da build mais recente. O nome do arquivo `.msix` usa 3 partes
(`InvTec-X.Y.Z.msix`), mas o atributo `Version="..."` dentro do XML usa 4
partes (`X.Y.Z.0`) — essa é a Version real dentro do pacote (ver "Fonte
única de versão" acima); as duas vêm do mesmo `pubspec.yaml` e sempre
batem automaticamente.

Comportamento de update configurado nele:

- `HoursBetweenUpdateChecks="0"` — verifica a cada abertura do app
  (adequado para a fase atual de testes internos; revisar quando sair de
  fase de validação, se quiser menos verificações).
- `ShowPrompt="true"` — avisa o usuário que existe atualização.
- `UpdateBlocksActivation="false"` — nova versão disponível não impede
  abrir o app na versão atual enquanto o usuário não atualizar
  (arquitetura já preparada para mudar isso no futuro, se quisermos
  atualização obrigatória).

## Hospedagem — Supabase Storage (bucket `invtec-updates`) é o host oficial

**Decisão:** o GitHub Releases foi testado e **confirmado incompatível**
(serve todo asset como `Content-Type: application/octet-stream`,
independente da extensão — testado empiricamente contra uma release
pública real de outro repositório; não há como configurar isso por
arquivo no GitHub). Por isso o host oficial do App Installer passa a ser
o **Supabase Storage do próprio projeto InvTec** (mesmo projeto, nenhum
projeto novo criado), bucket dedicado `invtec-updates`. GitHub Releases
continua existindo apenas como backup/distribuição secundária opcional —
não é mais a origem referenciada dentro do `.appinstaller`.

**PROJECT_REF**: `xbqjeztuizydtxliwooe` (lido de `SUPABASE_URL` no `.env`
local já existente — não é segredo, é a mesma URL pública que o próprio
app Flutter já usa para falar com o Supabase).

**URL base final** (`INVTEC_UPDATE_BASE_URL`):

```
https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates
```

Esse é o padrão público oficial do Supabase Storage para um bucket
`public` — qualquer arquivo dentro dele fica acessível em
`<essa-url>/<nome-do-arquivo>`, sem autenticação, sem expor nenhuma
chave/secret.

### Estrutura do bucket

```
invtec-updates/
  InvTec.appinstaller       <- sobrescrito a cada release (cache baixo)
  InvTec-1.0.0.msix         <- nunca sobrescrito (cache longo)
  InvTec-1.0.1.msix
  InvTec-1.0.2.msix
  ...
```

### Procedimento manual — criar o bucket (Supabase Dashboard)

Nenhum destes passos foi executado por esta tarefa — é o roteiro para
você rodar manualmente. Não automatizar ainda com credencial
administrativa.

1. Dashboard do projeto InvTec → **Storage** → **New bucket**.
2. Nome: `invtec-updates`.
3. Marcar **Public bucket** (os instaladores precisam ser baixáveis sem
   autenticação pelo Windows App Installer).
4. Não aplicar nenhuma policy de RLS adicional além do padrão de bucket
   público — este bucket é isolado e não tem relação com as tabelas de
   negócio do InvTec (nenhuma RLS existente foi tocada).

### Procedimento manual — upload do `.msix`

1. Storage → bucket `invtec-updates` → **Upload file**.
2. Selecionar `dist\windows\InvTec-X.Y.Z.msix` (ex. `InvTec-1.0.0.msix`
   — gerado por `build_installer.ps1`).
3. **Garantir o MIME correto antes/durante o upload** — não confiar na
   inferência automática por extensão: no diálogo de upload do Supabase
   Dashboard, defina explicitamente **Content-Type: `application/msix`**
   (o Dashboard permite definir/editar o MIME do objeto; se o upload
   simples não expuser esse campo, use "Edit" no arquivo já enviado para
   corrigir o `Content-Type` antes de validar com o preflight).
4. Cache: pode usar cache **longo** (ex. `Cache-Control: public,
   max-age=31536000, immutable`) — o nome do arquivo já é único por
   versão, nunca é reescrito.
5. Repetir para cada versão nova — **nunca sobrescrever** um `.msix` já
   publicado.

### Procedimento manual — upload do `InvTec.appinstaller`

1. Storage → bucket `invtec-updates` → **Upload file** (ou "Replace", se
   já existir de uma release anterior).
2. Selecionar `dist\windows\InvTec.appinstaller` (gerado por
   `generate_appinstaller.ps1` com `-BaseUrl` apontando para a URL do
   bucket acima).
3. **Content-Type: `application/appinstaller`** — mesma observação do
   `.msix`: definir explicitamente, não confiar na inferência por
   extensão.
4. Cache: usar cache **baixo** (ex. `Cache-Control: no-cache` ou
   `max-age=60`) — este arquivo muda a cada release e **precisa** ser
   revalidado a cada abertura do InvTec; evite qualquer CDN/cache
   intermediário entregando uma versão antiga.
5. **Sempre sobrescrever** este arquivo (mesmo nome, mesma URL) — nunca
   publicar `InvTec-1.0.1.appinstaller` como arquivo separado; a URL
   estável é o próprio contrato com os clientes já instalados.

### Obter as URLs públicas

No Supabase Dashboard, Storage → bucket → arquivo → "Get URL" (ou
compor manualmente: `<URL base>/<nome-do-arquivo>`). URLs finais
esperadas:

```
https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates/InvTec.appinstaller
https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates/InvTec-1.0.0.msix
```

### Automação futura (não feita agora)

Depois que o fluxo manual funcionar de ponta a ponta, decidir se vale
automatizar o upload no GitHub Actions com um secret do Supabase
(`SUPABASE_ACCESS_TOKEN`/service key do Storage, nunca a service_role de
banco) — **não implementado nesta tarefa**, por decisão explícita.

## GitHub Actions (preparado, não acionado)

`.github/workflows/windows-release.yml` builda, assina e publica uma
GitHub Release ao dar push numa tag `v*` (ex. `v1.0.0`) — ou manualmente
em "Run workflow". **Nenhuma tag foi criada e nenhum release foi
publicado por esta tarefa.**

Secrets/variáveis que precisam existir no repositório (Settings →
Secrets and variables → Actions) **antes** do primeiro uso real:

| Nome | Tipo | Conteúdo |
|---|---|---|
| `INVTEC_SIGNING_CERTIFICATE_BASE64` | Secret | `certs/InvTec.pfx` codificado em base64 (`[Convert]::ToBase64String([IO.File]::ReadAllBytes("certs\InvTec.pfx")) \| Set-Clipboard`) |
| `INVTEC_SIGNING_CERTIFICATE_PASSWORD` | Secret | Senha do `.pfx` |
| `INVTEC_UPDATE_BASE_URL` | Variable (não-secret) | `https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates` |

O certificado chega ao job só como secret, é materializado em arquivo
temporário (`RUNNER_TEMP`) durante o job, e é removido no fim (passo
`if: always()`). Nunca é commitado nem aparece em log — o GitHub Actions
mascara automaticamente qualquer valor igual a um secret registrado.

**Nenhum secret do Supabase foi adicionado ao workflow nesta tarefa** —
o upload para o bucket `invtec-updates` continua manual (ver
"Hospedagem" acima). O workflow continua só produzindo MSIX +
AppInstaller + GitHub Release (backup); ele já aceita qualquer valor em
`INVTEC_UPDATE_BASE_URL`, então nenhuma mudança de código foi necessária
ali além de atualizar o valor documentado da variável.

## Instalador simplificado para usuários

Para a primeira instalação nos computadores dos funcionários, em vez do
procedimento manual (importar certificado via PowerShell admin, baixar o
`.appinstaller`, abrir), existe um instalador de ~1 clique.

Para distribuir, enviar o pacote `InvTec_Instalador.zip` com estes 3
arquivos juntos (conteúdo de `dist/installer/`):

```
InvTec_Instalador.zip
├── Instalar InvTec.bat
├── installer_payload.ps1
└── InvTec.cer
```

Os 3 arquivos precisam estar na **mesma pasta** depois de extraídos — o
`.bat` localiza os outros dois ao lado dele (`%~dp0`/`$PSScriptRoot`),
sem depender de nenhum caminho fixo.

**Nunca** incluir `InvTec.pfx`, a senha do certificado, ou qualquer outro
segredo — só o `.cer` (certificado público).

O funcionário:

1. extrai o ZIP;
2. executa `Instalar InvTec.bat`;
3. aceita o UAC;
4. aguarda;
5. abre o InvTec pelo Menu Iniciar.

**Design deliberado — sem Base64, sem `Invoke-Expression`:** o `.bat` é só
um launcher mínimo (eleva via UAC se necessário, chama
`installer_payload.ps1` com `powershell -ExecutionPolicy Bypass -File` e
propaga o código de saída) — nenhuma lógica de certificado/download/
instalação fica nele. Toda essa lógica mora em
`installer_payload.ps1` (também versionado em
`scripts/windows/installer_payload.ps1` como fonte canônica; a cópia em
`dist/installer/` é só o artefato de distribuição), **em texto plano,
auditável abrindo o arquivo normalmente** — nada embutido/codificado.
Isso reduz a chance de falso positivo de antivírus/EDR (que tendem a
desconfiar de Base64 executável + `Invoke-Expression` em `.bat`) e
facilita revisão e manutenção futura.

O `-ExecutionPolicy Bypass` é passado **só nessa chamada do processo**
`powershell.exe` — nunca altera a política do Windows (usuário ou
máquina) de forma permanente, e só executa o arquivo local específico
`installer_payload.ps1` ao lado do `.bat`, nunca um script baixado da
internet.

O que `installer_payload.ps1` faz:

1. Resolve seu próprio caminho via `$PSScriptRoot` para achar o
   `InvTec.cer` ao lado.
2. Verifica o `InvTec.cer`: Subject precisa ser `CN=GETEC` e Thumbprint
   precisa ser `FDB7FF97F58D1804C06ED8F4AC2ECD9F72537036` exatos.
   Qualquer divergência **aborta sem instalar nada**.
3. Instala o certificado em `Cert:\LocalMachine\TrustedPeople` — mas só se
   ainda não estiver lá (detecta pelo Thumbprint; reexecução é segura, não
   duplica, só avisa "já confiável").
4. Baixa `InvTec.appinstaller` da URL oficial do Supabase Storage para
   `%TEMP%`.
5. Instala via `Add-AppxPackage -AppInstallerFile` (não instala o `.msix`
   isolado) — preserva a associação de atualização automática.
6. Apaga o `.appinstaller` temporário; nunca apaga o `InvTec.cer` da pasta
   distribuída; nunca desinstala/limpa dados em reexecução.

Mensagens de progresso `[1/4]`...`[4/4]`; em qualquer falha mostra a etapa
e a mensagem, sem fechar a janela (`pause` no final, no `.bat`) para o
usuário poder ler e procurar o suporte de TI.

A elevação (detecção de admin + reinício via UAC) fica no `.bat`, não no
`.ps1` — por isso ele consegue ser mínimo e ainda assim nunca pedir para
o usuário abrir PowerShell manualmente, nunca desligar UAC/SmartScreen/
Defender.

Só serve para a **primeira instalação**. Depois disso, atualizações
futuras continuam acontecendo automaticamente pelo App Installer (ver
"Comportamento de update" acima) — este `.bat`/`.ps1` não participam
disso.

### Primeira instalação — procedimento manual (alternativa/fallback)

Caso prefira não usar o `.bat`, ou para entender o que ele automatiza:

1. Copiar `certs/InvTec.cer` para a máquina e instalar/confiar nele
   (duplo clique → "Instalar certificado" → "Pessoas Confiáveis", ou via
   painel de administração de TI). Isso só precisa ser feito **uma vez**
   por máquina, não a cada atualização.
2. Abrir `InvTec.appinstaller` (link ou arquivo) → "Instalar".
3. InvTec aparece como aplicativo instalado no Windows normalmente.

Não desligar o SmartScreen/segurança do Windows como "solução" — o passo
1 (confiar no certificado) é o caminho correto.

## Procedimento — primeira release (v1.0.0)

Nenhum destes passos foi executado por esta tarefa (nenhuma tag, nenhum
release, versão do pubspec não alterada) — é o roteiro para você rodar.

1. **Certificado** (uma vez só): `scripts\windows\create_signing_certificate.ps1`.
2. **Instalar o `.cer` na(s) máquina(s) de teste** (ver "Primeira
   instalação" abaixo) — precisa ser feito antes do passo 8.
3. **Bump de versão**: `pubspec.yaml` → `version: 1.0.0+1` (ou o que já
   estiver lá, se ainda não tiver sido publicado nenhuma vez).
4. **Build assinado local**:
   `scripts\windows\build_installer.ps1 -RunTests -CertificatePath certs\InvTec.pfx`
   → gera `dist\windows\InvTec-1.0.0.msix`.
5. **Gerar o appinstaller**:
   `scripts\windows\generate_appinstaller.ps1 -BaseUrl "https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates"`
   → gera `dist\windows\InvTec.appinstaller` (`Version="1.0.0.0"` dentro
   do XML, apontando para `InvTec-1.0.0.msix`).
6. **(Opcional) GitHub Release como backup**:
   `git tag v1.0.0 && git push origin v1.0.0` (dispara o workflow) OU
   publicar manualmente — só para ter os artefatos arquivados, não é a
   origem usada pelo App Installer.
7. **Upload manual para o Supabase Storage** — seguir "Procedimento
   manual — upload do `.msix`" e "... do `InvTec.appinstaller`" acima
   (bucket `invtec-updates`, MIME explícito, cache correto em cada um).
8. **Validar os headers** (`verify_release_artifacts.ps1`, seção própria
   abaixo) antes de confiar no host.
9. **Instalar numa máquina limpa** (sem InvTec instalado) seguindo
   "Primeira instalação numa máquina nova".

## Procedimento — release de teste de update (v1.0.1)

Objetivo: confirmar que uma instalação v1.0.0 já existente detecta e
instala v1.0.1 sozinha, sem perder dados/preferências locais.

1. Fazer uma mudança **visual simples e segura** (ex.: só o número da
   versão mesmo, nada de lógica) e bump em `pubspec.yaml` →
   `version: 1.0.1+2` (incrementa o PATCH — obrigatório, ver "Fonte única
   de versão").
2. `scripts\windows\build_installer.ps1 -RunTests -CertificatePath certs\InvTec.pfx`
   → gera `dist\windows\InvTec-1.0.1.msix` (mesmo certificado do v1.0.0
   — isso é o que faz o Windows reconhecer como upgrade do mesmo
   publisher, não como um app novo).
3. `scripts\windows\generate_appinstaller.ps1 -BaseUrl "https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates"`
   → `InvTec.appinstaller` agora aponta `Version="1.0.1.0"` e para
   `InvTec-1.0.1.msix`.
4. **Upload manual para o Supabase Storage**:
   - `InvTec-1.0.1.msix` → upload novo (não sobrescreve o `1.0.0`),
     MIME `application/msix`, cache longo.
   - `InvTec.appinstaller` → **sobrescrever** o existente, MIME
     `application/appinstaller`, cache baixo.
5. (Opcional) tag/release no GitHub como backup, igual ao v1.0.0.
6. Validar os headers de novo (seção abaixo) — confirmar que o
   `InvTec.appinstaller` já reflete `Version="1.0.1.0"` (não ficou
   servindo uma cópia antiga via cache).
7. Na máquina de teste já com v1.0.0 instalado: abrir o InvTec → como
   `HoursBetweenUpdateChecks="0"`, ele consulta o appinstaller a cada
   abertura → deve aparecer o prompt de atualização (`ShowPrompt="true"`)
   → aceitar → confirmar que atualiza para 1.0.1 → ver "Confirmar que a
   atualização funcionou" abaixo.
8. Não usar dados patrimoniais reais nesse teste.

## Validar os headers do host

```powershell
scripts\windows\verify_release_artifacts.ps1 -BaseUrl "https://xbqjeztuizydtxliwooe.supabase.co/storage/v1/object/public/invtec-updates" -Version "1.0.0"
```

(`-Version` aqui é a versão de 3 partes do `.msix`, ex. `1.0.0` — igual
ao nome do arquivo no bucket.) Exige, para os 2 arquivos, falhando
claramente (exit code 1) se qualquer um não bater:

- status HTTP 200/206 (acessível);
- `Content-Length` presente;
- `Content-Type` **exatamente** `application/appinstaller` (para o
  `.appinstaller`) ou `application/msix` (para o `.msix`) — comparação
  do media-type, ignorando parâmetro extra tipo `;charset=...` se vier.

Script validado nesta tarefa contra chamadas HTTP reais (`Invoke-WebRequest`
funcionando normalmente neste ambiente) — a lógica de acesso/headers/
comparação de Content-Type foi testada isoladamente e está correta; o
que falta é rodá-lo contra o bucket `invtec-updates` depois do primeiro
upload real, que não foi feito nesta tarefa (upload é manual, por
decisão explícita).

## Confirmar que a atualização automática funcionou

- Abrir **Configurações → Sobre** no InvTec depois do update — deve
  mostrar `InvTec — Versão 1.0.1` (lido do pacote instalado via
  `package_info_plus`, nunca hardcoded — se mostrar 1.0.1, o binário
  realmente foi substituído, não é só o instalador tendo rodado).
- Confirmar nas Configurações do Windows → Apps instalados → InvTec →
  versão também bate.
- Confirmar que preferências locais (tema claro/escuro, sidebar
  colapsada, etc. — `SharedPreferences`) continuam as mesmas de antes do
  update.
- Fazer login e confirmar que o Supabase continua funcionando
  normalmente.
- Confirmar que **nenhuma migration/SQL** foi executada pela atualização
  do MSIX — ela nunca deve tocar no Supabase (nenhum SQL automático,
  nenhuma migration disparada pelo instalador); migrations continuam
  processo administrativo manual separado, documentado em
  `supabase/manual/deployment_procedure.md`.

## Pontos de segurança (resumo)

- Nenhuma `service_role key` no app nem nos scripts — o bucket
  `invtec-updates` é **público** de propósito (os instaladores não são
  segredo) e o upload manual usa as credenciais do Dashboard do
  administrador, nunca uma chave embutida em código.
- Bucket `invtec-updates` é isolado: nenhuma RLS de tabela de negócio do
  InvTec foi criada/alterada, nenhuma migration foi criada, o Postgres
  do projeto não foi tocado — é só armazenamento de arquivo estático.
- `.pfx`/senha do certificado: nunca no Git, nunca em log — só em
  `certs/` local (ignorado) ou em GitHub Secrets.
- `msix_config` só declara a capability `internetClient` (o InvTec
  precisa de internet para o Supabase) — nenhuma capability de
  câmera/microfone/localização/etc.
