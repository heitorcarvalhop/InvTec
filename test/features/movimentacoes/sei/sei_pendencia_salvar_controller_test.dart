import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_analyzer.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_pendencia_builder.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_analise_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_pendencia_salvar_controller.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../fake_movimentacao_repository.dart';
import 'fake_documentos_sei_repository.dart';

final _setorGetec = Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorGeasi = Setor(id: 'setor-geasi', nome: 'Gerência de Licenciamento', sigla: 'GEASI', ativo: true, criadoEm: DateTime(2026, 1, 1));

PatrimonioDetalhe _patrimonio() {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'id-4157090',
      numeroPatrimonio: '4157090',
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-getec',
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'Gerencia de Tecnologia',
  );
}

SeiAnaliseResultado _resultado() {
  final documento = SeiDocumentoExtraido(
    nomeArquivo: 'doc.pdf',
    tamanhoBytes: 100,
    quantidadePaginas: 1,
    hashSha256: 'h',
    numeroDocumentoSei: '95955192',
    numeroProcesso: '202600017000011',
    tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
    itens: [
      SeiItemExtraido(
        linha: 1,
        paginaOrigem: 1,
        numeroPatrimonio: '4157090',
        equipamento: 'Monitor Positivo',
        unidadeOrigemTexto: 'GETEC - Gerencia de Tecnologia',
        unidadeDestinoTexto: 'Gerência de Licenciamento – GEASI',
        numeroChamado: '4556',
      ),
    ],
  );
  return const SeiDocumentoAnalyzer().analisar(
    documento: documento,
    patrimoniosPorNumero: {'4157090': _patrimonio()},
    setoresAtivos: [_setorGetec, _setorGeasi],
  );
}

void main() {
  group('PROMPT 11.3 — SeiPendenciaSalvarController', () {
    test('sem duplicata: salva direto e o documento sai como sucesso', () async {
      final docRepo = FakeDocumentosSeiRepository();
      final container = ProviderContainer(overrides: [documentosSeiRepositoryProvider.overrideWithValue(docRepo)]);
      addTearDown(container.dispose);

      final notifier = container.read(seiPendenciaSalvarControllerProvider.notifier);
      await notifier.salvar(resultado: _resultado(), execucao: const {});

      final state = container.read(seiPendenciaSalvarControllerProvider);
      expect(state.status, SeiSalvarPendenciaStatus.sucesso);
      expect(state.documentoSalvo, isNotNull);
      expect(docRepo.criarCallCount, 1);
    });

    test('documento já existente com o mesmo número SEI: fica aguardando confirmação, NUNCA salva sozinho', () async {
      final docRepo = FakeDocumentosSeiRepository();
      await docRepo.salvarRascunho(
        construirDocumentoPendenteRascunho(resultado: _resultado(), execucao: const {})!,
      );

      final container = ProviderContainer(overrides: [documentosSeiRepositoryProvider.overrideWithValue(docRepo)]);
      addTearDown(container.dispose);

      final notifier = container.read(seiPendenciaSalvarControllerProvider.notifier);
      await notifier.salvar(resultado: _resultado(), execucao: const {});

      final state = container.read(seiPendenciaSalvarControllerProvider);
      expect(state.status, SeiSalvarPendenciaStatus.aguardandoConfirmacaoDuplicidade);
      expect(state.duplicatas, hasLength(1));
      // Continua havendo só 1 documento — a segunda tentativa NÃO salvou
      // sozinha.
      expect(docRepo.criarCallCount, 1);
    });

    test('confirmarApesarDeDuplicata salva mesmo assim, criando um segundo documento', () async {
      final docRepo = FakeDocumentosSeiRepository();
      await docRepo.salvarRascunho(
        construirDocumentoPendenteRascunho(resultado: _resultado(), execucao: const {})!,
      );

      final container = ProviderContainer(overrides: [documentosSeiRepositoryProvider.overrideWithValue(docRepo)]);
      addTearDown(container.dispose);

      final notifier = container.read(seiPendenciaSalvarControllerProvider.notifier);
      await notifier.salvar(resultado: _resultado(), execucao: const {});
      expect(
        container.read(seiPendenciaSalvarControllerProvider).status,
        SeiSalvarPendenciaStatus.aguardandoConfirmacaoDuplicidade,
      );

      await notifier.confirmarApesarDeDuplicata();

      final state = container.read(seiPendenciaSalvarControllerProvider);
      expect(state.status, SeiSalvarPendenciaStatus.sucesso);
      expect(docRepo.criarCallCount, 2);
    });

    test(
      'PROMPT 11.3, seção 19 — nenhuma ação de salvar/cancelar pendência chama registrar_movimentacao',
      () async {
        final docRepo = FakeDocumentosSeiRepository();
        final movimentacaoRepo = FakeMovimentacaoRepository();
        final container = ProviderContainer(
          overrides: [
            documentosSeiRepositoryProvider.overrideWithValue(docRepo),
            movimentacaoRepositoryProvider.overrideWithValue(movimentacaoRepo),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(seiPendenciaSalvarControllerProvider.notifier);
        await notifier.salvar(resultado: _resultado(), execucao: const {});
        final documento = container.read(seiPendenciaSalvarControllerProvider).documentoSalvo!;

        await docRepo.cancelarItem(itemId: documento.itens.single.id, motivo: 'Teste');

        expect(movimentacaoRepo.registrarCallCount, 0);
        expect(movimentacaoRepo.listarCallCount, 0);
        expect(movimentacaoRepo.listarPorNumeroDocumentoCallCount, 0);
      },
    );
  });
}
