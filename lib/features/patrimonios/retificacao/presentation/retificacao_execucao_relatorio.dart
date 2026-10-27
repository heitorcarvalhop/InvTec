import 'package:csv/csv.dart';

import 'retificacao_controller.dart';

/// Rótulo em PT-BR de [ItemExecucaoRetificacaoStatus] para a coluna
/// "Resultado" do relatório final — o enum técnico nunca aparece
/// diretamente no CSV.
String rotuloStatusExecucaoRetificacao(ItemExecucaoRetificacaoStatus status) {
  switch (status) {
    case ItemExecucaoRetificacaoStatus.pendente:
      return 'Pendente (não processado)';
    case ItemExecucaoRetificacaoStatus.executando:
      return 'Em execução';
    case ItemExecucaoRetificacaoStatus.sucesso:
      return 'Retificado com sucesso';
    case ItemExecucaoRetificacaoStatus.falha:
      return 'Falha (nada foi gravado)';
    case ItemExecucaoRetificacaoStatus.resultadoDesconhecido:
      return 'Resultado desconhecido (tentar novamente)';
  }
}

/// Gera o relatório CSV FINAL de uma rodada de execução — só LEITURA do
/// estado já resolvido em memória (nenhuma consulta nova). Uma linha por
/// item executado, na mesma ordem em que entraram na rodada.
String gerarCsvExecucaoRetificacao(Map<String, ItemExecucaoRetificacaoEstado> itensExecucao) {
  final linhas = <List<String>>[
    [
      'ID patrimônio',
      'Tombamento',
      'Unidade de destino',
      'Resultado',
      'Mensagem',
      'ID da movimentação',
      'Concluído em',
    ],
    for (final estado in itensExecucao.values)
      [
        estado.item.patrimonioId,
        estado.item.numeroPatrimonioExibicao ?? estado.item.tombamentoEsperado,
        estado.item.setorDestinoNomeExibicao ?? '',
        rotuloStatusExecucaoRetificacao(estado.status),
        estado.falha?.message ?? '',
        estado.resultado?.movimentacaoId ?? '',
        estado.resultado?.concluidoEm?.toIso8601String() ?? '',
      ],
  ];
  return const CsvEncoder().convert(linhas);
}
