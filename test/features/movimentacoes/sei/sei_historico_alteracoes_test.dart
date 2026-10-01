import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/documentos_sei_repository.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// "Histórico de alterações" do detalhe de um documento SEI
/// pendente: reaproveita inteiramente `documentos_sei_eventos` via
/// `DocumentosSeiRepository.listarEventos` (nenhuma tabela nova, nenhuma
/// escrita própria). Reproduz, contra o fake, o MESMO caso real registrado
/// no Supabase no documento fictício
/// `999999/2026/TESTE-PROMPT1137`: chamado do patrimônio 900000001 corrigido
/// de 9999 para 9998, motivo "Teste funcional de edição de pendência".

Profile _profile() => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

final _setorGetec = Setor(
  id: 'setor-getec',
  nome: 'Gerencia de Tecnologia',
  sigla: 'GETEC',
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
);
final _setorNtat = Setor(
  id: 'setor-ntat',
  nome: 'Nucleo de Testes Automatizados',
  sigla: 'NTAT',
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
);

SeiItemPendente _itemFicticio({int linha = 1, String numero = '900000001'}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: 'doc-teste',
    linha: linha,
    numeroPatrimonio: SeiValorCorrigivel(original: numero),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC - Gerencia de Tecnologia'),
    origemSetorId: 'setor-getec',
    destinoTexto: const SeiValorCorrigivel(original: 'Nucleo de Testes Automatizados - NTAT'),
    numeroChamado: const SeiValorCorrigivel(original: '9999'),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Monitor Ficticio Teste'),
    status: SeiItemPendenciaStatus.pendente,
    criadoEm: DateTime(2026, 1, 1),
  );
}

SeiDocumentoPendente _documentoFicticio({List<SeiItemPendente>? itens}) {
  return SeiDocumentoPendente.fromItens(
    id: 'doc-teste',
    numeroDocumentoSei: '99999999',
    numeroProcesso: '202699999999999',
    numeroDocumentoFormatado: '999999/2026/TESTE-PROMPT1137',
    assunto: 'TESTE AUTOMATIZADO (PROMPT 11.3.7) - Transferencia de patrimonio ficticio',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'despacho_TESTE_PROMPT_11_3_7.pdf',
    hashSha256: 'hash-teste',
    versao: 1,
    criadoEm: DateTime(2026, 1, 1),
    criadoPorId: 'user-1',
    criadoPorNome: 'Fulano de Teste',
    itens: itens ?? [_itemFicticio()],
  );
}

Future<void> _pumpDetalhe(
  WidgetTester tester,
  DocumentosSeiRepository repositorio, {
  List<Setor> setores = const [],
}) async {
  final fakeAuth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _profile());
  addTearDown(fakeAuth.dispose);

  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        documentosSeiRepositoryProvider.overrideWithValue(repositorio),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores)),
        localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSeiPendenciaDetalheDialog(context, 'doc-teste'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _expandirHistorico(WidgetTester tester) async {
  final tile = find.text('Histórico de alterações');
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  group('histórico de alterações do documento SEI', () {
    testWidgets('sem nenhum evento, mostra a mensagem de ausência (nunca uma lista vazia silenciosa)', (tester) async {
      final repo = FakeDocumentosSeiRepository(documentosIniciais: [_documentoFicticio()]);
      await _pumpDetalhe(tester, repo);

      await _expandirHistorico(tester);

      expect(find.text('Nenhum evento registrado para este documento ainda.'), findsOneWidget);
    });

    testWidgets(
      'edição: mostra um caso real (chamado do patrimônio 900000001 de 9999 para 9998, com motivo)',
      (tester) async {
        final repo = FakeDocumentosSeiRepository(documentosIniciais: [_documentoFicticio()]);
        await repo.editarDocumento(
          documentoId: 'doc-teste',
          versaoEsperada: 1,
          motivo: 'Teste funcional de edição de pendência',
          itensAlterados: {'item-1': const SeiItemPendenteEdicao(numeroChamadoCorrigido: '9998')},
        );

        await _pumpDetalhe(tester, repo);
        await _expandirHistorico(tester);

        expect(find.text('Edição de dados'), findsOneWidget);
        expect(find.text('Patrimônio 900000001'), findsOneWidget);
        expect(find.text('Número do chamado'), findsOneWidget);
        expect(find.text('9999'), findsOneWidget);
        // Uma vez no histórico (valor novo) e outra na coluna Chamado da
        // ficha (valor efetivo atual do item).
        expect(find.text('9998'), findsNWidgets(2));
        expect(find.text('Motivo'), findsOneWidget);
        expect(find.text('Teste funcional de edição de pendência'), findsOneWidget);
      },
    );

    testWidgets('edição: mudança de assunto do documento mostra o valor anterior e o novo', (tester) async {
      final repo = FakeDocumentosSeiRepository(documentosIniciais: [_documentoFicticio()]);
      await repo.editarDocumento(
        documentoId: 'doc-teste',
        versaoEsperada: 1,
        motivo: 'Corrigindo assunto do despacho fictício',
        assunto: () => 'Assunto corrigido para o teste',
      );

      await _pumpDetalhe(tester, repo);
      await _expandirHistorico(tester);

      expect(find.text('Assunto'), findsOneWidget);
      expect(find.text('TESTE AUTOMATIZADO (PROMPT 11.3.7) - Transferencia de patrimonio ficticio'), findsOneWidget);
      expect(find.text('Assunto corrigido para o teste'), findsOneWidget);
    });

    testWidgets(
      'valores longos: anterior, seta e novo ficam empilhados, na largura toda e claramente associados',
      (tester) async {
        const antes = 'TESTE AUTOMATIZADO (PROMPT 11.3.7) - Transferencia de patrimonio ficticio';
        const depois =
            'TESTE AUTOMATIZADO — EDIÇÃO CONFIRMADA — assunto novo propositalmente longo para forçar a quebra '
            'de linha dentro da própria linha do valor, sem espremer o valor anterior';
        final repo = FakeDocumentosSeiRepository(documentosIniciais: [_documentoFicticio()]);
        await repo.editarDocumento(
          documentoId: 'doc-teste',
          versaoEsperada: 1,
          motivo: 'Corrigindo assunto',
          assunto: () => depois,
        );

        await _pumpDetalhe(tester, repo);
        await _expandirHistorico(tester);

        final rotulo = tester.getRect(find.text('Assunto'));
        final rAntes = tester.getRect(find.text(antes));
        final rDepois = tester.getRect(find.text(depois));
        final seta = tester.getRect(find.text('→'));

        // Os dois valores começam no MESMO x (coluna de valores) e o novo vem
        // abaixo do anterior — nunca lado a lado em metades da largura.
        expect(rDepois.left, rAntes.left);
        expect(rDepois.top, greaterThanOrEqualTo(rAntes.bottom));
        expect(rAntes.top, greaterThanOrEqualTo(rotulo.bottom), reason: 'valores logo abaixo do nome do campo');

        // A seta e o rótulo "Depois" ficam à esquerda do valor novo, na sua
        // primeira linha; "Antes" alinha com o valor anterior.
        expect(seta.right, lessThanOrEqualTo(rDepois.left));
        expect(seta.center.dy, inInclusiveRange(rDepois.top, rDepois.top + 24));
        expect(find.text('Antes'), findsOneWidget);
        expect(find.text('Depois'), findsOneWidget);
        expect(tester.getRect(find.text('Antes')).right, lessThanOrEqualTo(rAntes.left));

        // Uma linha por valor usa a largura da lista, não metade dela.
        expect(rAntes.width, greaterThan(400));
      },
    );

    testWidgets('edição: setor de destino resolvido aparece pela sigla, nunca pelo UUID bruto', (tester) async {
      final repo = FakeDocumentosSeiRepository(documentosIniciais: [_documentoFicticio()]);
      await repo.editarDocumento(
        documentoId: 'doc-teste',
        versaoEsperada: 1,
        motivo: 'Resolvendo o setor de destino fictício',
        itensAlterados: {'item-1': SeiItemPendenteEdicao(destinoSetorId: () => 'setor-ntat')},
      );

      await _pumpDetalhe(tester, repo, setores: [_setorGetec, _setorNtat]);
      await _expandirHistorico(tester);

      expect(find.text('Setor de destino resolvido'), findsOneWidget);
      expect(find.text('NTAT'), findsOneWidget);
      expect(find.text('setor-ntat'), findsNothing, reason: 'nunca mostra o UUID bruto como apresentação principal');
    });

    testWidgets('cancelamento individual: mostra o motivo e identifica o item pelo número do patrimônio', (
      tester,
    ) async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documentoFicticio(
            itens: [
              _itemFicticio(),
              _itemFicticio(linha: 2, numero: '900000002'),
            ],
          ),
        ],
      );
      await repo.cancelarItem(itemId: 'item-1', motivo: 'Item cancelado individualmente para o teste');

      await _pumpDetalhe(tester, repo);
      await _expandirHistorico(tester);

      expect(find.text('Item cancelado'), findsOneWidget);
      expect(find.text('Item afetado: Patrimônio 900000001 (linha 1)'), findsOneWidget);
      expect(find.text('Item cancelado individualmente para o teste'), findsOneWidget);
    });

    testWidgets('cancelamento em massa: informa quantos itens pendentes foram afetados', (tester) async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documentoFicticio(
            itens: [
              _itemFicticio(),
              _itemFicticio(linha: 2, numero: '900000002'),
            ],
          ),
        ],
      );
      await repo.cancelarPendentesDoDocumento(
        documentoId: 'doc-teste',
        motivo: 'Cancelando tudo para encerrar o teste',
      );

      await _pumpDetalhe(tester, repo);
      await _expandirHistorico(tester);

      expect(find.text('Itens pendentes cancelados'), findsOneWidget);
      expect(find.text('2 item(ns) pendente(s) cancelado(s): Cancelando tudo para encerrar o teste'), findsOneWidget);
    });

    testWidgets('vários eventos aparecem do mais recente para o mais antigo', (tester) async {
      final repo = FakeDocumentosSeiRepository(documentosIniciais: [_documentoFicticio()]);
      await repo.editarDocumento(documentoId: 'doc-teste', versaoEsperada: 1, motivo: 'Primeira edição');
      await repo.editarDocumento(documentoId: 'doc-teste', versaoEsperada: 2, motivo: 'Segunda edição');

      await _pumpDetalhe(tester, repo);
      await _expandirHistorico(tester);

      final ordem = tester.widgetList<Text>(find.textContaining('edição')).map((t) => t.data).toList();
      final indiceSegunda = ordem.indexOf('Segunda edição');
      final indicePrimeira = ordem.indexOf('Primeira edição');
      expect(indiceSegunda, greaterThanOrEqualTo(0));
      expect(indicePrimeira, greaterThanOrEqualTo(0));
      expect(indiceSegunda, lessThan(indicePrimeira), reason: 'mais recente primeiro');
    });
  });
}
