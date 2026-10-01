import '../../domain/movimentacao.dart';
import '../../domain/movimentacao_listagem_item.dart';
import '../domain/sei_duplicidade.dart';

/// Classifica a duplicidade de UM item contra o histórico já lido em lote
/// pelo controller (nunca uma consulta por linha — mesma disciplina do
/// cruzamento com patrimônios/setores). Função pura: não lê nada, só
/// compara o que já foi buscado.
SeiDuplicidadeResultado classificarDuplicidade({
  required String patrimonioId,
  required MovimentacaoTipo? tipoProposto,
  required String? destinoIdProposto,
  required String? numeroChamadoProposto,
  required List<MovimentacaoListagemItem> historicoDoDocumento,
}) {
  final doPatrimonio = historicoDoDocumento.where((m) => m.patrimonioId == patrimonioId).toList();

  if (doPatrimonio.isEmpty) {
    return const SeiDuplicidadeResultado(
      status: SeiDuplicidadeStatus.semCorrespondencia,
      detalhe: 'Nenhuma movimentação deste patrimônio referencia este documento SEI.',
    );
  }

  final mesmoTipo = doPatrimonio.where((m) => m.tipo == tipoProposto).toList();

  if (mesmoTipo.isEmpty) {
    return SeiDuplicidadeResultado(
      status: SeiDuplicidadeStatus.exigeRevisao,
      correspondente: doPatrimonio.first,
      detalhe:
          'Já existe movimentação deste patrimônio para este documento SEI, mas de tipo diferente '
          '(${doPatrimonio.first.tipo.label}) — confira se a interpretação do documento ainda se aplica.',
    );
  }

  final identica = mesmoTipo.where(
    (m) => m.setorDestinoId == destinoIdProposto && (m.numeroChamado ?? '') == (numeroChamadoProposto ?? ''),
  );

  if (identica.isNotEmpty) {
    return SeiDuplicidadeResultado(
      status: SeiDuplicidadeStatus.jaRegistrada,
      correspondente: identica.first,
      detalhe: 'Já existe uma movimentação idêntica (mesmo tipo, destino e chamado) para este documento SEI.',
    );
  }

  return SeiDuplicidadeResultado(
    status: SeiDuplicidadeStatus.possivelDuplicidade,
    correspondente: mesmoTipo.first,
    detalhe:
        'Existe movimentação deste patrimônio para este documento SEI, do mesmo tipo, mas com destino ou '
        'chamado diferentes do que o documento propõe agora — confira antes de prosseguir.',
  );
}
