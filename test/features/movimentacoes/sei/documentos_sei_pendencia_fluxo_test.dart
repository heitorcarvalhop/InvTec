import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/domain/documentos_sei_repository.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_situacao.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_evento_documento.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart';

import 'fake_documentos_sei_repository.dart';

SeiItemPendenteRascunho _itemRascunho(int linha, {String? patrimonioId}) {
  return SeiItemPendenteRascunho(
    linha: linha,
    patrimonioId: patrimonioId ?? 'pat-$linha',
    numeroPatrimonioOriginal: '400000$linha',
    origemTextoOriginal: 'GETEC',
    origemSetorId: 'setor-getec',
    destinoTextoOriginal: 'GEASI',
    destinoSetorId: 'setor-geasi',
    numeroChamadoOriginal: '4556',
    equipamentoTextoOriginal: 'Monitor',
  );
}

SeiDocumentoPendenteRascunho _rascunho({
  int qtdItens = 1,
  String numeroDocumentoSei = '95955192',
  String? numeroProcesso = '202600017000011',
}) {
  return SeiDocumentoPendenteRascunho(
    numeroDocumentoSei: numeroDocumentoSei,
    numeroProcesso: numeroProcesso,
    numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
    assunto: 'Transferência de bens',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'despacho.pdf',
    hashSha256: 'hash-fake',
    itens: [for (var i = 1; i <= qtdItens; i++) _itemRascunho(i)],
  );
}

void main() {
  group('PROMPT 11.3, seção 19 — fluxo de Documentos SEI pendentes (fake, mesmas regras da migration proposta)', () {
    test('salvar rascunho cria uma solicitação PENDENTE — nunca altera um patrimônio', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho());

      expect(repo.criarCallCount, 1);
      expect(documento.situacao, SeiDocumentoSituacao.pendente);
      expect(documento.itens.single.status, SeiItemPendenciaStatus.pendente);
      // A garantia "nunca altera um patrimônio" é estrutural: nada neste
      // arquivo, nem em `DocumentosSeiRepository`, referencia
      // `PatrimonioRepository` ou grava em `patrimonios` — só cria linhas
      // em `documentos_sei`/`documentos_sei_itens` (ver migration proposta).
    });

    test('33 itens pendentes: todos nascem PENDENTE, nenhum concluído/cancelado', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho(qtdItens: 33));

      expect(documento.totalItens, 33);
      expect(documento.totalPendentes, 33);
      expect(documento.totalConcluidos, 0);
      expect(documento.totalCancelados, 0);
      expect(documento.situacao, SeiDocumentoSituacao.pendente);
    });

    test('primeira conclusão bloqueia edição global (dados principais e itens)', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho(qtdItens: 2));
      final itemA = documento.itens[0];

      repo.marcarItemConcluidoParaTeste(itemA.id, movimentacaoId: 'mov-1');

      expect(
        () => repo.editarDocumento(
          documentoId: documento.id,
          versaoEsperada: 2, // já incrementada pela conclusão simulada
          motivo: 'Corrigir assunto',
          assunto: () => 'Assunto corrigido',
        ),
        throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()),
      );
    });

    test('itens restantes continuam concluíveis/canceláveis mesmo com o documento bloqueado para edição', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho(qtdItens: 2));
      final itemA = documento.itens[0];
      final itemB = documento.itens[1];

      repo.marcarItemConcluidoParaTeste(itemA.id, movimentacaoId: 'mov-1');

      final atualizado = await repo.cancelarItem(itemId: itemB.id, motivo: 'Item não faz mais sentido');
      expect(atualizado.itens.firstWhere((i) => i.id == itemB.id).status, SeiItemPendenciaStatus.cancelado);
    });

    test('item concluído nunca pode ser cancelado/alterado de novo', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho());
      final item = documento.itens.single;

      repo.marcarItemConcluidoParaTeste(item.id, movimentacaoId: 'mov-1');

      expect(
        () => repo.cancelarItem(itemId: item.id, motivo: 'Tentativa indevida'),
        throwsA(isA<SeiItemNaoElegivelException>()),
      );
    });

    test('cancelamento parcial não desfaz conclusões anteriores', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho(qtdItens: 3));
      final itemConcluido = documento.itens[0];

      repo.marcarItemConcluidoParaTeste(itemConcluido.id, movimentacaoId: 'mov-1');
      final atualizado = await repo.cancelarPendentesDoDocumento(documentoId: documento.id, motivo: 'Resto cancelado');

      expect(atualizado.itens.firstWhere((i) => i.id == itemConcluido.id).status, SeiItemPendenciaStatus.concluido);
      expect(atualizado.itens.firstWhere((i) => i.id == itemConcluido.id).movimentacaoId, 'mov-1');
      expect(atualizado.totalCancelados, 2);
    });

    test('cancelamento total (sem conclusões) deixa o documento CANCELADO', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho(qtdItens: 3));

      final atualizado = await repo.cancelarPendentesDoDocumento(documentoId: documento.id, motivo: 'Despacho revogado');
      expect(atualizado.situacao, SeiDocumentoSituacao.cancelado);
    });

    test('documento com conclusões E cancelamentos, sem pendências, fica ENCERRADO_PARCIALMENTE', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho(qtdItens: 3));
      final itemConcluido = documento.itens[0];

      repo.marcarItemConcluidoParaTeste(itemConcluido.id, movimentacaoId: 'mov-1');
      final atualizado = await repo.cancelarPendentesDoDocumento(documentoId: documento.id, motivo: 'Restante cancelado');

      expect(atualizado.situacao, SeiDocumentoSituacao.encerradoParcialmente);
    });

    test('correção manual preserva o valor original — nunca sobrescrito', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho());
      final item = documento.itens.single;
      expect(item.destinoTexto.original, 'GEASI');

      final editado = await repo.editarDocumento(
        documentoId: documento.id,
        versaoEsperada: 1,
        motivo: 'Destino estava errado no PDF',
        itensAlterados: {item.id: const SeiItemPendenteEdicao(destinoTextoCorrigido: 'GESOL')},
      );

      final itemEditado = editado.itens.single;
      expect(itemEditado.destinoTexto.original, 'GEASI', reason: 'original nunca é sobrescrito');
      expect(itemEditado.destinoTexto.corrigido, 'GESOL');
      expect(itemEditado.destinoTexto.valorEfetivo, 'GESOL');
      expect(itemEditado.destinoTexto.foiCorrigido, isTrue);
    });

    test(
      'PROMPT 11.3.1, seção 3 — editarDocumento agora também corrige destino resolvido, localização e '
      'responsável (a versão original só corrigia texto, contrariando a seção 8 do PROMPT 11.3)',
      () async {
        final repo = FakeDocumentosSeiRepository();
        final documento = await repo.salvarRascunho(_rascunho());
        final item = documento.itens.single;
        expect(item.destinoSetorId, 'setor-geasi');
        expect(item.decisaoLocalizacao, SeiDecisaoCampo.pendente);

        final editado = await repo.editarDocumento(
          documentoId: documento.id,
          versaoEsperada: 1,
          motivo: 'Destino/localização/responsável revisados',
          itensAlterados: {
            item.id: SeiItemPendenteEdicao(
              destinoSetorId: () => 'setor-gesol',
              localizacaoDestinoId: () => 'loc-1',
              decisaoLocalizacao: SeiDecisaoCampo.definido,
              responsavelDestino: () => 'Fulano de Tal',
              decisaoResponsavel: SeiDecisaoCampo.definido,
            ),
          },
        );

        final itemEditado = editado.itens.single;
        expect(itemEditado.destinoSetorId, 'setor-gesol');
        expect(itemEditado.localizacaoDestinoId, 'loc-1');
        expect(itemEditado.decisaoLocalizacao, SeiDecisaoCampo.definido);
        expect(itemEditado.responsavelDestino, 'Fulano de Tal');
        expect(itemEditado.decisaoResponsavel, SeiDecisaoCampo.definido);
      },
    );

    test('duas edições concorrentes: a segunda, com versão desatualizada, é rejeitada', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho());
      expect(documento.versao, 1);

      // Sessão A lê versão 1 e edita com sucesso.
      final aposA = await repo.editarDocumento(
        documentoId: documento.id,
        versaoEsperada: 1,
        motivo: 'Sessão A corrige o assunto',
        assunto: () => 'Assunto corrigido por A',
      );
      expect(aposA.versao, 2);

      // Sessão B também tinha lido versão 1 (antes de A salvar) e tenta
      // editar agora — deve ser rejeitada, nunca sobrescrever A "por cima".
      expect(
        () => repo.editarDocumento(
          documentoId: documento.id,
          versaoEsperada: 1,
          motivo: 'Sessão B tenta editar com versão desatualizada',
          assunto: () => 'Assunto de B',
        ),
        throwsA(
          isA<SeiEdicaoConflitoException>()
              .having((e) => e.versaoEsperada, 'versaoEsperada', 1)
              .having((e) => e.versaoAtual, 'versaoAtual', 2),
        ),
      );
    });

    test('tentativa de editar após conclusão registrada por outra sessão — mesmo com a versão certa', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho());
      final item = documento.itens.single;

      // "Outra sessão" conclui o item entre a leitura e esta tentativa —
      // a versão do documento já reflete essa mudança (2).
      final aposConclusao = repo.marcarItemConcluidoParaTeste(item.id, movimentacaoId: 'mov-1');
      expect(aposConclusao.versao, 2);

      // Mesmo enviando a versão CORRETA e atual (2), a edição continua
      // bloqueada — a regra de "documento com item concluído" prevalece
      // sobre o controle de versão, nunca o contrário.
      expect(
        () => repo.editarDocumento(
          documentoId: documento.id,
          versaoEsperada: 2,
          motivo: 'Tentativa de editar depois da conclusão',
          assunto: () => 'Novo assunto',
        ),
        throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()),
      );
    });

    test('mesmo documento reimportado não duplica silenciosamente: buscarPossivelDuplicata encontra o anterior', () async {
      final repo = FakeDocumentosSeiRepository();
      await repo.salvarRascunho(_rascunho());

      final duplicatas = await repo.buscarPossivelDuplicata(
        numeroDocumentoSei: '95955192',
        numeroProcesso: '202600017000011',
      );
      expect(duplicatas, hasLength(1));
    });

    test(
      'PROMPT 11.3.1, seção 8 — salvarRascunho REJEITA um segundo documento ativo com o mesmo número '
      'sem confirmarDuplicata (fecha a corrida "duas sessões salvando ao mesmo tempo")',
      () async {
        final repo = FakeDocumentosSeiRepository();
        await repo.salvarRascunho(_rascunho());

        expect(
          () => repo.salvarRascunho(_rascunho()),
          throwsA(isA<SeiDocumentoDuplicadoException>()),
        );
        expect(repo.criarCallCount, 1, reason: 'a segunda tentativa nunca chegou a criar nada');
      },
    );

    test('confirmarDuplicata: true ainda permite o reimport legítimo, criando um segundo documento', () async {
      final repo = FakeDocumentosSeiRepository();
      await repo.salvarRascunho(_rascunho());

      await repo.salvarRascunho(_rascunho(), confirmarDuplicata: true);
      expect(repo.criarCallCount, 2);

      final duplicatasApos = await repo.buscarPossivelDuplicata(numeroDocumentoSei: '95955192');
      expect(duplicatasApos, hasLength(2), reason: 'os dois documentos coexistem — nada os fundiu silenciosamente');
    });

    test('documento anterior CANCELADO não conta como duplicata ativa — reimport sem confirmarDuplicata é aceito', () async {
      final repo = FakeDocumentosSeiRepository();
      final primeiro = await repo.salvarRascunho(_rascunho());
      await repo.cancelarPendentesDoDocumento(documentoId: primeiro.id, motivo: 'Despacho revogado');

      // Sem confirmarDuplicata — deve funcionar, pois o único documento
      // existente com este número já está totalmente CANCELADO.
      final segundo = await repo.salvarRascunho(_rascunho());
      expect(repo.criarCallCount, 2);
      expect(segundo.situacao, SeiDocumentoSituacao.pendente);
    });

    // PROMPT 11.3.2 — testes adicionados pela nova auditoria (seção 6).
    // IMPORTANTE: `FakeDocumentosSeiRepository` é single-threaded (chamadas
    // Dart sequenciais, nunca duas transações reais concorrentes) — os
    // testes abaixo comprovam o CONTRATO exposto ao chamador (o que a UI/o
    // controller veem), nunca a garantia de concorrência real no
    // PostgreSQL (trava consultiva, `for update`), que só um banco real
    // pode validar (seção 7/10 do relatório).

    test(
      'PROMPT 11.3.2, seção 1 — "duas sessões" salvando o mesmo documento: a segunda chamada (mesmo sem ver '
      'a primeira antes) é rejeitada pelo repositório, nunca cria um segundo documento silenciosamente',
      () async {
        final repo = FakeDocumentosSeiRepository();
        await repo.salvarRascunho(_rascunho());

        // Segunda "sessão" tentando criar o MESMO documento sem saber da
        // primeira (não checou buscarPossivelDuplicata antes) — o
        // repositório (equivalente ao banco) recusa mesmo assim.
        expect(() => repo.salvarRascunho(_rascunho()), throwsA(isA<SeiDocumentoDuplicadoException>()));
        expect(repo.criarCallCount, 1);
      },
    );

    test(
      'PROMPT 11.3.2, seção 2 — cancelamento parcial sem nenhuma conclusão mantém a situação PENDENTE, '
      'mesmo com itens já cancelados (a view SQL corrigida segue a mesma regra)',
      () async {
        final repo = FakeDocumentosSeiRepository();
        final documento = await repo.salvarRascunho(_rascunho(qtdItens: 3));

        final atualizado = await repo.cancelarItem(itemId: documento.itens[0].id, motivo: 'Item duplicado no despacho');

        expect(atualizado.totalConcluidos, 0);
        expect(atualizado.totalCancelados, 1);
        expect(atualizado.totalPendentes, 2);
        expect(atualizado.situacao, SeiDocumentoSituacao.pendente);
      },
    );

    test(
      'PROMPT 11.3.2, seção 3 — tentativa bloqueada de editar não deixa NENHUM evento persistido '
      '(a versão anterior prometia um evento TENTATIVA_BLOQUEADA que a exceção desfazia)',
      () async {
        final repo = FakeDocumentosSeiRepository();
        final documento = await repo.salvarRascunho(_rascunho());
        repo.marcarItemConcluidoParaTeste(documento.itens.single.id, movimentacaoId: 'mov-1');

        final eventosAntes = await repo.listarEventos(documento.id);

        await expectLater(
          repo.editarDocumento(
            documentoId: documento.id,
            versaoEsperada: 2,
            motivo: 'Tentativa bloqueada',
            assunto: () => 'Novo assunto',
          ),
          throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()),
        );

        final eventosDepois = await repo.listarEventos(documento.id);
        expect(eventosDepois, hasLength(eventosAntes.length), reason: 'nenhum evento novo — nem "bloqueada"');
        expect(eventosDepois.any((e) => e.tipo == SeiTipoEventoDocumento.tentativaBloqueada), isFalse);
      },
    );

    test(
      'PROMPT 11.3.2, seção 4 — editar com item_id inexistente rejeita a operação INTEIRA, '
      'nenhum campo do documento nem dos itens válidos muda',
      () async {
        final repo = FakeDocumentosSeiRepository();
        final documento = await repo.salvarRascunho(_rascunho(qtdItens: 2));
        final itemValido = documento.itens[0];

        await expectLater(
          repo.editarDocumento(
            documentoId: documento.id,
            versaoEsperada: 1,
            motivo: 'Tenta corrigir item válido + item inexistente',
            assunto: () => 'Assunto que NÃO deveria ser salvo',
            itensAlterados: {
              itemValido.id: const SeiItemPendenteEdicao(destinoTextoCorrigido: 'GESOL'),
              'item-inexistente-999': const SeiItemPendenteEdicao(destinoTextoCorrigido: 'GESOL'),
            },
          ),
          throwsA(isA<SeiItemEdicaoInvalidaException>()),
        );

        final recarregado = await repo.obterPorId(documento.id);
        expect(recarregado.versao, 1, reason: 'nada foi commitado');
        expect(recarregado.assunto, documento.assunto);
        expect(recarregado.itens.firstWhere((i) => i.id == itemValido.id).destinoTexto.foiCorrigido, isFalse);
      },
    );

    test('PROMPT 11.3.2, seção 4 — editar referenciando um item de OUTRO documento é rejeitado', () async {
      final repo = FakeDocumentosSeiRepository();
      final documentoA = await repo.salvarRascunho(_rascunho(numeroDocumentoSei: '11111111'));
      final documentoB = await repo.salvarRascunho(_rascunho(numeroDocumentoSei: '22222222'));
      final itemDeB = documentoB.itens.single;

      expect(
        () => repo.editarDocumento(
          documentoId: documentoA.id,
          versaoEsperada: 1,
          motivo: 'Tenta corrigir item de outro documento',
          itensAlterados: {itemDeB.id: const SeiItemPendenteEdicao(destinoTextoCorrigido: 'GESOL')},
        ),
        throwsA(isA<SeiItemEdicaoInvalidaException>()),
      );
    });

    test(
      'PROMPT 11.3.3, seção 3 — mesmo SEI, uma sessão sem processo e outra COM processo, ainda são '
      'detectadas como duplicata (nos dois sentidos — a checagem não depende de qual roda primeiro)',
      () async {
        // Sentido 1: cria SEM processo primeiro, depois tenta COM processo.
        final repoA = FakeDocumentosSeiRepository();
        await repoA.salvarRascunho(_rascunho(numeroProcesso: null));
        expect(
          () => repoA.salvarRascunho(_rascunho(numeroProcesso: '202600017000011')),
          throwsA(isA<SeiDocumentoDuplicadoException>()),
        );

        // Sentido 2 (inverso): cria COM processo primeiro, depois tenta SEM processo.
        final repoB = FakeDocumentosSeiRepository();
        await repoB.salvarRascunho(_rascunho(numeroProcesso: '202600017000011'));
        expect(
          () => repoB.salvarRascunho(_rascunho(numeroProcesso: null)),
          throwsA(isA<SeiDocumentoDuplicadoException>()),
        );
      },
    );

    test('PROMPT 11.3.2, seção 4 — editar um item já CANCELADO é rejeitado (não pode mais ser corrigido)', () async {
      final repo = FakeDocumentosSeiRepository();
      final documento = await repo.salvarRascunho(_rascunho(qtdItens: 2));
      final itemCancelado = documento.itens[0];
      await repo.cancelarItem(itemId: itemCancelado.id, motivo: 'Não se aplica mais');

      expect(
        () => repo.editarDocumento(
          documentoId: documento.id,
          versaoEsperada: 2,
          motivo: 'Tenta corrigir item cancelado',
          itensAlterados: {itemCancelado.id: const SeiItemPendenteEdicao(destinoTextoCorrigido: 'GESOL')},
        ),
        throwsA(isA<SeiItemEdicaoInvalidaException>()),
      );
    });
  });
}
