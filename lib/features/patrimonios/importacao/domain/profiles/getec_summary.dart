import '../import_column_field.dart';
import '../import_row.dart';

/// Resumo específico do perfil GETEC (seção 28) — complementa o resumo
/// genérico (Prontos/Avisos/Erros/...), nunca o substitui.
class GetecResumo {
  const GetecResumo({
    required this.tiposIdentificados,
    required this.naoIdentificados,
    required this.tombamentosAnterioresEncontrados,
    required this.seriesNaoInformadas,
    required this.possiveisSeriesRepetidas,
    required this.linhasComPossivelBaixa,
  });

  factory GetecResumo.fromRows(List<ImportRow> linhas, Map<String, String> nomePorTipoId) {
    final contagemPorTipo = <String, int>{};
    var naoIdentificados = 0;
    var tombamentos = 0;
    var seriesVazias = 0;
    var duplicidadeSerial = 0;
    var baixas = 0;

    for (final linha in linhas) {
      // Tipo só se aplica a cadastro novo — atualizar() não tem esse campo.
      if (linha.existenteNoBanco == null) {
        final tipoId = linha.tipoIdResolvido;
        if (tipoId != null) {
          final nome = nomePorTipoId[tipoId] ?? tipoId;
          contagemPorTipo.update(nome, (valor) => valor + 1, ifAbsent: () => 1);
        } else {
          naoIdentificados++;
        }
      }

      if (linha.celulas[ImportColumnField.tombamentoAnterior] != null) tombamentos++;
      if (linha.celulas.containsKey(ImportColumnField.numeroSerie) && linha.numeroSerie == null) {
        seriesVazias++;
      }
      if (linha.possivelDuplicidadeSerial) duplicidadeSerial++;
      if (linha.possivelBaixa) baixas++;
    }

    final tipos = contagemPorTipo.entries.map((e) => GetecTipoContagem(nome: e.key, quantidade: e.value)).toList()
      ..sort((a, b) => b.quantidade.compareTo(a.quantidade));

    return GetecResumo(
      tiposIdentificados: tipos,
      naoIdentificados: naoIdentificados,
      tombamentosAnterioresEncontrados: tombamentos,
      seriesNaoInformadas: seriesVazias,
      possiveisSeriesRepetidas: duplicidadeSerial,
      linhasComPossivelBaixa: baixas,
    );
  }

  final List<GetecTipoContagem> tiposIdentificados;
  final int naoIdentificados;
  final int tombamentosAnterioresEncontrados;
  final int seriesNaoInformadas;
  final int possiveisSeriesRepetidas;
  final int linhasComPossivelBaixa;
}

class GetecTipoContagem {
  const GetecTipoContagem({required this.nome, required this.quantidade});

  final String nome;
  final int quantidade;
}
