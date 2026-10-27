import 'package:csv/csv.dart';

import 'retificacao_comparacao.dart';

/// Rótulo em PT-BR de cada [ClassificacaoRetificacao] para a coluna
/// "Classificação" do relatório — o enum técnico nunca aparece
/// diretamente no CSV.
String rotuloClassificacaoRetificacao(ClassificacaoRetificacao classificacao) {
  switch (classificacao) {
    case ClassificacaoRetificacao.pronto:
      return 'Pronto para retificar';
    case ClassificacaoRetificacao.jaNaUnidadeCorreta:
      return 'Já na unidade correta';
    case ClassificacaoRetificacao.patrimonioNaoEncontrado:
      return 'Patrimônio não encontrado';
    case ClassificacaoRetificacao.tombamentoDivergente:
      return 'Tombamento divergente do plano';
    case ClassificacaoRetificacao.setorAtualDivergente:
      return 'Unidade atual divergente do plano';
    case ClassificacaoRetificacao.unidadeDestinoNaoCadastrada:
      return 'Unidade de destino não cadastrada';
    case ClassificacaoRetificacao.unidadeDestinoInativa:
      return 'Unidade de destino inativa';
  }
}

/// Gera o relatório CSV do PLANO comparado (prévia) — uma linha por
/// [RetificacaoItem], na mesma ordem em que aparecem no CSV original. Só
/// LEITURA dos dados já resolvidos em memória; nunca inclui o resultado de
/// execução (ver `gerarCsvExecucaoRetificacao`, presentation/
/// retificacao_execucao_relatorio.dart, para o relatório FINAL pós-
/// execução).
String gerarCsvPlanoRetificacao(RetificacaoLote lote) {
  final linhas = <List<String>>[
    [
      'Linha no CSV',
      'ID patrimônio',
      'Tombamento',
      'Classificação',
      'Unidade atual',
      'Unidade de destino',
      'Motivo do bloqueio',
    ],
    for (final item in lote.itens)
      [
        '${item.linha.numeroLinha}',
        item.linha.patrimonioId,
        item.linha.tombamentoAtualInvtec,
        rotuloClassificacaoRetificacao(item.classificacao),
        item.patrimonioDetalhe?.setorExibidoCompacto ?? item.linha.setorAtualTexto,
        item.setorDestinoNome ?? item.linha.unidadeCorretaSigla,
        item.motivoBloqueio ?? '',
      ],
  ];
  return const CsvEncoder().convert(linhas);
}
