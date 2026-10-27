import 'package:csv/csv.dart';

import 'inventario_rapido.dart';
import 'patrimonio_scanner.dart';

/// Rótulo em PT-BR de cada [ScannerResultadoTipo] para a coluna "Status"
/// do relatório — o enum técnico nunca aparece diretamente no CSV.
String rotuloStatusInventario(ScannerResultadoTipo tipo) {
  switch (tipo) {
    case ScannerResultadoTipo.encontradoAtual:
      return 'Encontrado';
    case ScannerResultadoTipo.encontradoAnterior:
      return 'Encontrado (tombamento anterior)';
    case ScannerResultadoTipo.ambiguo:
      return 'Ambíguo (mais de uma correspondência)';
    case ScannerResultadoTipo.naoEncontrado:
      return 'Não encontrado';
    case ScannerResultadoTipo.codigoInvalido:
      return 'Código inválido';
    case ScannerResultadoTipo.acessoInsuficiente:
      return 'Acesso insuficiente para confirmar';
    case ScannerResultadoTipo.falhaConsulta:
      return 'Falha de consulta';
  }
}

/// Gera o relatório CSV de uma sessão de Inventário Rápido — só LEITURA
/// dos dados já resolvidos em memória (nenhuma consulta nova, nenhuma
/// escrita). Uma linha por [InventarioLeitura], na mesma ordem em que
/// aparecem na sessão.
String gerarCsvInventario({
  required String localizacaoSelecionadaNome,
  required String localizacaoSelecionadaId,
  required List<InventarioLeitura> leituras,
}) {
  final linhas = <List<String>>[
    [
      'Código lido',
      'Status',
      'Número de patrimônio',
      'Equipamento',
      'Localização cadastrada',
      'Localização conferida',
      'Localização divergente',
      'Lido em',
    ],
    for (final leitura in leituras)
      [
        leitura.codigoLido,
        rotuloStatusInventario(leitura.status),
        leitura.patrimonioUnico?.patrimonio.numeroPatrimonio ?? '',
        leitura.patrimonioUnico?.tipoNome ?? '',
        leitura.patrimonioUnico?.localizacaoNome ?? '',
        localizacaoSelecionadaNome,
        leitura.patrimonioUnico == null
            ? ''
            : (leituraDivergeDaLocalizacao(leitura, localizacaoSelecionadaId)
                  ? 'SIM'
                  : 'NÃO'),
        leitura.lidoEm.toIso8601String(),
      ],
  ];
  return const CsvEncoder().convert(linhas);
}
