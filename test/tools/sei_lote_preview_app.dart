// =============================================================================
// PRÉVIA LOCAL DA CONCLUSÃO EM LOTE (SEI), SOMENTE DADOS
// FICTÍCIOS.
// =============================================================================
// Entrypoint EXCLUSIVO de desenvolvimento — nunca usado pelo app operacional
// (lib/main.dart não é tocado, nenhuma rota nova foi adicionada a ele; este
// arquivo não fica em lib/ — ver o comentário "POR QUE test/tools", abaixo).
//
//   * NÃO chama `Supabase.initialize` — nenhuma URL/chave/credencial real é
//     lida ou usada.
//   * NÃO existe nenhum código aqui que fale com a rede: todo repositório é
//     um FAKE EM MEMÓRIA (os MESMOS fakes já usados pelos testes de widget
//     — `FakeDocumentosSeiRepository`/`FakePatrimonioRepository`/
//     `FakeAuthRepository` — reaproveitados de propósito, para a prévia
//     nunca reimplementar regra de negócio nenhuma por conta própria).
//   * Usa os WIDGETS REAIS da funcionalidade
//     (`showSeiPendenciaDetalheDialog`, `sei_concluir_lote_dialog.dart` por
//     baixo) — isto não é uma reprodução visual artificial da tela.
//   * Nenhum patrimônio real, nenhum número de documento real, nenhum dado
//     do Despacho 577 é usado — tudo aqui é fabricado só para esta prévia.
//
// POR QUE test/tools, E NÃO lib/main_sei_lote_preview.dart:
//   O pedido original sugeria `lib/main_sei_lote_preview.dart`. Na prática,
//   o Dart/Flutter NÃO deixa um arquivo dentro de `lib/` importar, por
//   caminho relativo, um arquivo de FORA de `lib/` (o resolvedor de pacotes
//   trata `lib/` como a raiz de `package:invtec/...` e recusa `../test/...`
//   — confirmado com `flutter analyze`, erro `uri_does_not_exist`). Como o
//   objetivo era reaproveitar os fakes JÁ HOMOLOGADOS em `test/`, sem
//   duplicá-los, o entrypoint foi colocado aqui, em `test/tools/` — um
//   arquivo comum (`void main()`), SEM `import 'package:flutter_test/...'`,
//   SEM `test(...)`/`testWidgets(...)`: `flutter test` não o executa (só
//   roda arquivos `*_test.dart`), e `flutter run -t` aceita qualquer
//   caminho de arquivo como entrypoint, dentro ou fora de `lib/`.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_erros.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_conclusao_lote_controller.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

// Reaproveita os MESMOS fakes já homologados pela suíte de testes, em vez
// de escrever uma segunda simulação da RPC só para a prévia: a prévia nunca
// corre o risco de "inventar" um comportamento que diverge do que já foi
// auditado. Nenhum destes arquivos depende de `package:flutter_test` (só
// Dart/Flutter comuns).
import '../features/auth/fake_auth_repository.dart';
import '../features/movimentacoes/sei/fake_documentos_sei_repository.dart';
import '../features/patrimonios/fake_patrimonio_repository.dart';

const _docId = 'previa-doc-1';
const _usuarioPreviaId = 'previa-user-1';

/// SÓ para esta prévia: substitui `textoAvisoLote`
/// ("...movimentações patrimoniais reais...", em `sei_concluir_lote_dialog.dart`)
/// via o parâmetro opcional `textoAviso`/`textoAvisoConclusaoLote` — o
/// aviso de responsabilidade do app operacional continua o mesmo, sempre
/// que nenhum parâmetro é passado (o caso normal).
const _textoAvisoLoteFicticioPrevia =
    'PRÉVIA LOCAL: esta ação simula uma conclusão em lote inteiramente EM MEMÓRIA — nenhuma movimentação '
    'patrimonial real é registrada em lugar nenhum (nenhum banco, nenhuma rede). Os itens fictícios só ficam '
    '"concluídos" nesta sessão do aplicativo.';

void main() {
  // Sem `WidgetsFlutterBinding.ensureInitialized()`/`Supabase.initialize`
  // de propósito: esta prévia nunca toca rede.
  runApp(const SeiLotePreviewRoot());
}

/// Widget raiz — dono da "geração" do [ProviderScope]. "Reiniciar prévia"
/// troca a geração, o que força o Flutter a descartar TODOS os providers
/// (inclusive [seiConclusaoLoteControllerProvider] e os fakes) e montar um
/// conjunto novo — nenhum atalho de UI para "descartar" uma tentativa
/// pendente isoladamente (isso continua proibido, mesmo aqui). É a única
/// forma de "resetar" a prévia.
class SeiLotePreviewRoot extends StatefulWidget {
  const SeiLotePreviewRoot({super.key});

  @override
  State<SeiLotePreviewRoot> createState() => SeiLotePreviewRootState();
}

class SeiLotePreviewRootState extends State<SeiLotePreviewRoot> {
  int _geracao = 0;

  void _reiniciar() => setState(() => _geracao++);

  @override
  Widget build(BuildContext context) {
    final auth = FakeAuthRepository(
      initialUserId: _usuarioPreviaId,
      profileResolver: (id) => Profile(
        id: id,
        nome: 'Usuária da Prévia',
        email: 'previa@local.invalido',
        perfil: ProfilePerfil.admin,
        ativo: true,
        criadoEm: DateTime.utc(2026, 1, 1),
        atualizadoEm: DateTime.utc(2026, 1, 1),
      ),
    );
    final documento = documentoPreviewDemo();
    final repoPatrimonios = FakePatrimonioRepository(itens: patrimoniosPreviewDemo());
    // Conecta os dois fakes: sem isto, concluir um item
    // (individual ou em lote) atualiza o documento SEI mas NUNCA o cadastro
    // do patrimônio fictício (setor/localização/responsável atuais ficam
    // "congelados"), diferente da RPC real (que atualiza os dois na mesma
    // transação) — era exatamente o que a expansão do item mostrava de
    // errado ao reabrir DEMO-0023/DEMO-0024 concluídos nesta prévia.
    final repoDocumentos = FakeDocumentosSeiRepository(
      documentosIniciais: [documento],
      patrimonioRepository: repoPatrimonios,
    );

    return ProviderScope(
      key: ValueKey(_geracao),
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        documentosSeiRepositoryProvider.overrideWithValue(repoDocumentos),
        patrimonioRepositoryProvider.overrideWithValue(repoPatrimonios),
      ],
      child: MaterialApp(
        title: 'Prévia — Conclusão em lote SEI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // Identificação visível "PRÉVIA LOCAL — DADOS
        // FICTÍCIOS" em TODA tela desta prévia (não só na home), via
        // `builder`: qualquer diálogo/rota aberta por cima continua com a
        // faixa visível.
        builder: (context, child) => Banner(
          message: 'PRÉVIA LOCAL — DADOS FICTÍCIOS',
          location: BannerLocation.topEnd,
          color: Colors.deepOrange,
          child: child ?? const SizedBox.shrink(),
        ),
        home: _SeiLotePreviewHome(documento: documento, repo: repoDocumentos, onReiniciar: _reiniciar),
      ),
    );
  }
}

class _SeiLotePreviewHome extends ConsumerWidget {
  const _SeiLotePreviewHome({required this.documento, required this.repo, required this.onReiniciar});

  final SeiDocumentoPendente documento;
  final FakeDocumentosSeiRepository repo;
  final VoidCallback onReiniciar;

  Future<bool> _confirmarSeOcioso(BuildContext context, WidgetRef ref) async {
    final estado = ref.read(seiConclusaoLoteControllerProvider);
    if (estado.status == SeiConclusaoLoteStatus.ocioso) return true;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Já há uma tentativa em andamento'),
        content: Text(
          'O controlador de lote desta prévia já está em "${estado.status.name}". Isto é o MESMO comportamento '
          'do app real (o controller é global — uma decisão pendente bloqueia uma nova até ser resolvida). '
          'Abra o documento e resolva a tentativa pela própria tela, ou use "Reiniciar prévia" para começar do zero.',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Entendi'))],
      ),
    );
    return false;
  }

  /// A distinção certa é entre as DUAS coisas que este método faz:
  ///  * [modoFalha] não-nulo → vai ALTERAR `repo.falhaNaConclusao` para
  ///    simular uma FALHA NOVA na próxima escrita — isto é "preparar um
  ///    cenário", e continua exigindo o controller ocioso (requisito 6:
  ///    nunca preparar um cenário novo por cima de uma tentativa pendente
  ///    não resolvida — mesma regra de [_prepararConflitoDeIntegridade]);
  ///  * [modoFalha] nulo → só abre `showSeiPendenciaDetalheDialog` com o
  ///    MESMO documento/repositório/ProviderScope de sempre, sem tocar em
  ///    `repo.falhaNaConclusao` nem no controller — isto é indistinguível
  ///    de reabrir a tela no app real, e o app real NUNCA bloqueia abrir um
  ///    documento só porque há uma decisão de lote pendente em algum canto
  ///    (quem bloqueia é o próprio diálogo, item a item — este entrypoint
  ///    não deve reimplementar esse bloqueio de
  ///    forma mais restritiva do que o app real). Nenhuma decisão nova é
  ///    criada, nenhum `loteId` é gerado, o controller não é substituído
  ///    nem reiniciado, e nenhuma conclusão roda sozinha — é só a MESMA
  ///    tela sendo aberta de novo.
  Future<void> _abrirCenario(BuildContext context, WidgetRef ref, {Object? modoFalha}) async {
    if (modoFalha != null && !await _confirmarSeOcioso(context, ref)) return;
    repo.falhaNaConclusao = modoFalha;
    if (!context.mounted) return;
    try {
      // Substitui, SÓ nesta prévia, o aviso de
      // responsabilidade sobre movimentações REAIS (`textoAvisoLote`, em
      // `sei_concluir_lote_dialog.dart`) por uma indicação de que aqui é
      // tudo fictício/em memória — o app operacional continua chamando
      // `showSeiPendenciaDetalheDialog` sem este parâmetro (`null`), então
      // o aviso real nunca muda.
      await showSeiPendenciaDetalheDialog(
        context,
        documento.id,
        textoAvisoConclusaoLote: _textoAvisoLoteFicticioPrevia,
      );
    } finally {
      // Nunca deixa o modo simulado "vazar" para fora desta chamada — a
      // conclusão INDIVIDUAL (e qualquer outro cenário) volta a funcionar
      // normalmente assim que este diálogo fechar.
      repo.falhaNaConclusao = null;
    }
  }

  /// Choreografa uma sequência: confirma uma decisão que "trava" em
  /// resultado desconhecido (timeout simulado) e, por fora do controller
  /// (como se fosse outra
  /// operação/outra aba reaproveitando o mesmo loteId), grava um registro
  /// DIVERGENTE para aquele mesmo `loteId` — nenhuma regra nova: só
  /// orquestra chamadas já existentes do fake/controller, para o usuário
  /// abrir o documento e ver o painel de conflito ao clicar em "Consultar o
  /// que aconteceu".
  Future<void> _prepararConflitoDeIntegridade(BuildContext context, WidgetRef ref) async {
    if (!await _confirmarSeOcioso(context, ref)) return;
    final notifier = ref.read(seiConclusaoLoteControllerProvider.notifier);
    final itemAlvo = documento.itens.first;
    final itemOutro = documento.itens[1];

    repo.falhaNaConclusao = Exception('timeout simulado (prévia) — resultado desconhecido');
    await notifier.confirmar(
      documentoId: documento.id,
      itemIds: [itemAlvo.id],
      versaoEsperada: documento.versao,
      confirmarLimpezaDestino: false,
    );
    repo.falhaNaConclusao = null;

    final loteId = ref.read(seiConclusaoLoteControllerProvider).decisao?.loteId;
    if (loteId == null) return; // não deveria acontecer; nada a semear.

    // Uma operação DIFERENTE (outro item) reaproveitou o mesmo loteId —
    // só possível de fabricar aqui porque é uma chamada direta ao fake,
    // nunca algo que a UI real permitiria.
    await repo.concluirItensLote(
      documentoId: documento.id,
      itemIds: [itemOutro.id],
      versaoEsperada: documento.versao,
      loteId: loteId,
      confirmarLimpezaDestino: false,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pronto: abra o documento, clique em "Concluir selecionados" e depois em '
          '"Consultar o que aconteceu" para ver o painel de conflito de integridade.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estadoLote = ref.watch(seiConclusaoLoteControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prévia — Conclusão em lote SEI (dados fictícios)'),
        backgroundColor: Colors.deepOrange.shade50,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    border: Border.all(color: Colors.deepOrange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PRÉVIA LOCAL — DADOS FICTÍCIOS. Nenhuma chamada de rede, nenhuma credencial, nenhum '
                    'patrimônio ou documento real é usado nesta tela. Tudo roda em memória, com os mesmos '
                    'widgets e o mesmo controlador do app real, sobre repositórios fictícios.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Estado atual do controlador de lote: ${estadoLote.status.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onReiniciar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reiniciar prévia (descarta tudo e recomeça do zero)'),
                ),
                const Divider(height: 32),
                Text('Cenário fictício', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  '25 itens fictícios no documento: 23 PENDENTES (1 já CONCLUÍDO e 1 já CANCELADO à parte). '
                  'Dos 23 pendentes: 17 elegíveis normais (para seleção múltipla/"concluir todos os aptos" — '
                  'lista longa, para testar a rolagem), 1 com origem DIVERGENTE (o patrimônio fictício está '
                  'hoje em outro setor — "concluir todos os aptos" já consulta o patrimônio atual e o EXCLUI '
                  'da seleção automática, com o motivo listado; selecioná-lo manualmente, porém, ainda bloqueia '
                  'o lote inteiro na revisão, para demonstrar essa proteção também na seleção explícita), 2 '
                  'BLOQUEADOS por decisão de destino pendente e 3 com limpeza de responsável/localização '
                  '(confirmação agregada) — um deles com descrição de equipamento propositalmente extensa. '
                  '"Concluir todos os aptos" propõe, no total, 20 itens (17 + os 3 de limpeza).',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _abrirCenario(context, ref),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Abrir documento (sempre permitido, mesmo com tentativa pendente)'),
                ),
                const SizedBox(height: 4),
                // A prévia deixava a impressão de
                // que TODA ação aqui embaixo era bloqueada por uma tentativa
                // pendente — na real, só PREPARAR um cenário NOVO é.
                const Text(
                  'Abrir o documento acima nunca é bloqueado, mesmo com uma tentativa de lote pendente '
                  '(resultado desconhecido/conflito) — é o mesmo comportamento do app real: quem bloqueia '
                  'escritas é o próprio diálogo, item a item, não a abertura da tela. É assim '
                  'que se chega a "Concluir selecionados" → "Consultar o que aconteceu" para resolver ou '
                  'demonstrar uma tentativa já preparada abaixo.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 24),
                Text('Simular desfechos da RPC de lote', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Cada botão PREPARA um cenário novo, definindo a resposta simulada do repositório fictício ANTES '
                  'de abrir o documento — depois, selecione itens e clique em "Concluir selecionados"/"Concluir '
                  'todos os aptos" para ver o painel correspondente. Diferente do botão "Abrir documento" acima, '
                  'PREPARAR um cenário novo continua BLOQUEADO enquanto já houver uma tentativa pendente (o '
                  'controller é global e a decisão fica congelada até ser resolvida) — resolva a tentativa atual '
                  '(ou "Reiniciar prévia") antes de preparar outra.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _abrirCenario(
                    context,
                    ref,
                    modoFalha: Exception('timeout simulado (prévia) — resultado desconhecido'),
                  ),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('Resultado desconhecido (timeout simulado)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _abrirCenario(
                    context,
                    ref,
                    modoFalha: falhaDeConclusaoSei(
                      codigo: 'P0010',
                      mensagemDoServidor: 'Conflito de edição simulado (prévia) — versão do documento mudou',
                      operacao: operacaoConcluirItensSeiLote,
                    ),
                  ),
                  icon: const Icon(Icons.error_outline),
                  label: const Text('Recusa conhecida (P0010 simulado)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _prepararConflitoDeIntegridade(context, ref),
                  icon: const Icon(Icons.report_gmailerrorred),
                  label: const Text('Preparar conflito de integridade (depois, abra o documento acima)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DADOS FICTÍCIOS — nenhum número de patrimônio/documento real, nenhum dado
// do Despacho 577.
// =============================================================================

SeiDocumentoPendente documentoPreviewDemo() {
  return SeiDocumentoPendente.fromItens(
    id: _docId,
    numeroDocumentoSei: '00000000',
    numeroDocumentoFormatado: 'PREVIA-000000/2026',
    numeroProcesso: 'PREVIA-00000.000000/2026-00',
    assunto: 'Prévia local de desenvolvimento — nenhum dado real',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'previa-ficticia.pdf',
    hashSha256: 'previa-hash-ficticio',
    versao: 1,
    criadoEm: DateTime.utc(2026, 1, 1),
    criadoPorId: _usuarioPreviaId,
    criadoPorNome: 'Usuária da Prévia',
    itens: _itensDemo(),
  );
}

/// FONTE ÚNICA de verdade por item: tanto [_itensDemo]
/// quanto [patrimoniosPreviewDemo] derivam do MESMO [_ItemFixture], para nunca
/// mais divergir por acidente entre "onde o documento diz que o patrimônio
/// está" (`origemSetorId`, no item) e "onde o patrimônio fictício
/// realmente está" (`setorAtualPatrimonioId`, no `Patrimonio`) — essa
/// divergência ACIDENTAL (gerar o setor de origem do item e o setor atual
/// do patrimônio de duas formas independentes) já bloqueou itens com
/// "Origem divergente" por engano. `setorAtualPatrimonioId` default PARA
/// `origemSetorId` — só diverge quando um item PROPOSITALMENTE precisa
/// disso (ver o item 18, abaixo), nunca por omissão.
class _ItemFixture {
  _ItemFixture({
    required this.linha,
    this.status = SeiItemPendenciaStatus.pendente,
    required this.origemSetorId,
    required this.origemSetorNome,
    this.destinoSetorId = 'setor-previa-ntat',
    this.destinoSetorNome = 'Núcleo de Testes (fictício)',
    this.decisaoLocalizacao = SeiDecisaoCampo.confirmadoSemInformacao,
    this.decisaoResponsavel = SeiDecisaoCampo.confirmadoSemInformacao,
    required this.equipamento,
    String? setorAtualPatrimonioId,
    this.comLimpeza = false,
  }) : setorAtualPatrimonioId = setorAtualPatrimonioId ?? origemSetorId;

  final int linha;
  final SeiItemPendenciaStatus status;
  final String origemSetorId;
  final String origemSetorNome;
  final String? destinoSetorId;
  final String? destinoSetorNome;
  final SeiDecisaoCampo decisaoLocalizacao;
  final SeiDecisaoCampo decisaoResponsavel;
  final String equipamento;

  /// Setor ATUAL do patrimônio fictício — usado só em [patrimoniosPreviewDemo].
  /// Igual a [origemSetorId] em qualquer item, exceto no item 18 (demo
  /// proposital de "Origem divergente").
  final String setorAtualPatrimonioId;
  final bool comLimpeza;
}

const _setoresDemo = [
  ('setor-previa-getec', 'Gerência de Tecnologia (fictícia)', 'setor-previa-ntat', 'Núcleo de Testes (fictício)'),
  ('setor-previa-almox', 'Almoxarifado (fictício)', 'setor-previa-ti', 'TI (fictícia)'),
  ('setor-previa-rh', 'Recursos Humanos (fictício)', 'setor-previa-fin', 'Financeiro (fictício)'),
];

List<_ItemFixture> _fixturesDemo() {
  final fixtures = <_ItemFixture>[];

  // 1-17: itens elegíveis "normais" — para seleção múltipla, "concluir
  // todos os aptos" e a rolagem da lista longa. `setorAtualPatrimonioId`
  // não é passado: por construção, o patrimônio fictício SEMPRE está no
  // mesmo setor que o item aponta como origem.
  for (var i = 1; i <= 17; i++) {
    final (origemId, origemNome, destinoId, destinoNome) = _setoresDemo[i % _setoresDemo.length];
    fixtures.add(
      _ItemFixture(
        linha: i,
        origemSetorId: origemId,
        origemSetorNome: origemNome,
        destinoSetorId: destinoId,
        destinoSetorNome: destinoNome,
        equipamento: 'Equipamento fictício $i',
      ),
    );
  }

  // 18: BLOQUEADO por ORIGEM DIVERGENTE, de propósito — o item aponta a
  // origem "Gerência de Tecnologia (fictícia)", mas o patrimônio fictício
  // está hoje em "Almoxarifado (fictício)" (`setorAtualPatrimonioId`
  // explicitamente diferente de `origemSetorId`).
  // "Concluir todos os aptos" já busca o patrimônio atual dos candidatos
  // e EXCLUI este item da seleção automática (com o motivo listado em
  // "não incluídos"); selecioná-lo manualmente ainda bloqueia o lote
  // inteiro na revisão — as duas proteções continuam demonstráveis.
  fixtures.add(
    _ItemFixture(
      linha: 18,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      setorAtualPatrimonioId: 'setor-previa-almox',
      equipamento: 'Equipamento fictício 18 (bloqueado — origem divergente do patrimônio)',
    ),
  );

  // 19-20: BLOQUEADOS — decisão de destino ainda pendente (impedem o lote
  // se selecionados explicitamente; aparecem em "não incluídos" no "todos
  // os aptos", já nesta primeira triagem — diferente do item 18).
  fixtures.add(
    _ItemFixture(
      linha: 19,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      decisaoLocalizacao: SeiDecisaoCampo.pendente,
      equipamento: 'Equipamento fictício 19 (bloqueado — localização)',
    ),
  );
  fixtures.add(
    _ItemFixture(
      linha: 20,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      decisaoResponsavel: SeiDecisaoCampo.pendente,
      equipamento: 'Equipamento fictício 20 (bloqueado — responsável)',
    ),
  );

  // 21-22: já CONCLUÍDO / já CANCELADO — nunca selecionáveis.
  fixtures.add(
    _ItemFixture(
      linha: 21,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      status: SeiItemPendenciaStatus.concluido,
      equipamento: 'Equipamento fictício 21 (já concluído)',
    ),
  );
  fixtures.add(
    _ItemFixture(
      linha: 22,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      status: SeiItemPendenciaStatus.cancelado,
      equipamento: 'Equipamento fictício 22 (já cancelado)',
    ),
  );

  // 23-25: exigem CONFIRMAÇÃO DE LIMPEZA (o patrimônio fictício tem
  // responsável/localização atuais — ver `patrimoniosPreviewDemo`); o item 23
  // também tem uma descrição de equipamento propositalmente extensa. Todos
  // com origem coerente (default).
  fixtures.add(
    _ItemFixture(
      linha: 23,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      comLimpeza: true,
      equipamento:
          'Notebook corporativo fictício, modelo de demonstração XPTO-9000, com carregador, mochila e mouse '
          'sem fio incluídos no mesmo tombamento — descrição propositalmente longa para testar o '
          'comportamento do texto na revisão do lote e na lista principal, inclusive em telas estreitas',
    ),
  );
  fixtures.add(
    _ItemFixture(
      linha: 24,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      comLimpeza: true,
      equipamento: 'Equipamento fictício 24 (com limpeza de responsável/localização)',
    ),
  );
  fixtures.add(
    _ItemFixture(
      linha: 25,
      origemSetorId: 'setor-previa-getec',
      origemSetorNome: 'Gerência de Tecnologia (fictícia)',
      comLimpeza: true,
      equipamento: 'Equipamento fictício 25 (com limpeza de responsável/localização)',
    ),
  );

  return fixtures;
}

List<SeiItemPendente> _itensDemo() {
  return [
    for (final f in _fixturesDemo())
      SeiItemPendente(
        id: 'previa-item-${f.linha}',
        documentoId: _docId,
        linha: f.linha,
        patrimonioId: 'previa-pat-${f.linha}',
        numeroPatrimonio: SeiValorCorrigivel(original: 'DEMO-${f.linha.toString().padLeft(4, '0')}'),
        origemTexto: SeiValorCorrigivel(original: f.origemSetorNome),
        origemSetorId: f.origemSetorId,
        origemSetorNome: f.origemSetorNome,
        destinoTexto: SeiValorCorrigivel(original: f.destinoSetorNome),
        destinoSetorId: f.destinoSetorId,
        destinoSetorNome: f.destinoSetorNome,
        numeroChamado: const SeiValorCorrigivel(original: null),
        equipamentoTexto: SeiValorCorrigivel(original: f.equipamento),
        decisaoLocalizacao: f.decisaoLocalizacao,
        decisaoResponsavel: f.decisaoResponsavel,
        status: f.status,
        criadoEm: DateTime.utc(2026, 1, 1),
      ),
  ];
}

List<PatrimonioDetalhe> patrimoniosPreviewDemo() {
  return [
    for (final f in _fixturesDemo())
      PatrimonioDetalhe(
        patrimonio: Patrimonio(
          id: 'previa-pat-${f.linha}',
          numeroPatrimonio: 'DEMO-${f.linha.toString().padLeft(4, '0')}',
          tipoId: 'previa-tipo-1',
          status: PatrimonioStatus.emUso,
          // Setor ATUAL do patrimônio fictício: igual à
          // origem do item em qualquer caso, exceto no item 18 (demo
          // proposital de "Origem divergente" — ver `_fixturesDemo`).
          setorAtualId: f.setorAtualPatrimonioId,
          responsavelAtual: f.comLimpeza ? 'Responsável Fictício ${f.linha}' : null,
          localizacaoAtualId: f.comLimpeza ? 'previa-localizacao-${f.linha}' : null,
          dataCadastro: DateTime.utc(2026, 1, 1),
          atualizadoEm: DateTime.utc(2026, 1, 1),
        ),
        tipoNome: 'Equipamento fictício',
        setorNome: _nomeDoSetor(f.setorAtualPatrimonioId),
        localizacaoNome: f.comLimpeza ? 'Sala fictícia ${f.linha}' : null,
      ),
  ];
}

/// Nome exibido (`PatrimonioDetalhe.setorNome`) para o setor ATUAL do
/// patrimônio fictício — precisa bater com o nome real daquele id, mesmo
/// quando é o setor "errado" do item 18 (senão a própria mensagem de
/// "Origem divergente" mostraria um nome incoerente com o id).
String _nomeDoSetor(String setorId) {
  for (final (id, nome, _, _) in _setoresDemo) {
    if (id == setorId) return nome;
  }
  return 'Setor fictício desconhecido';
}
