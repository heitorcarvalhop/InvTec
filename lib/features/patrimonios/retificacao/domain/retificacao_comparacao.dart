import '../../domain/patrimonio_detalhe.dart';
import '../../domain/tombamento_normalizacao.dart';
import '../../../setores/domain/setor.dart';
import 'retificacao_csv_linha.dart';

/// Classificação de UMA linha do plano de reclassificação, depois de
/// resolvida contra o estado REAL do InvTec — nunca contra o texto da
/// planilha isoladamente. Mutuamente exclusiva: cada linha cai em
/// EXATAMENTE uma categoria.
enum ClassificacaoRetificacao {
  /// Patrimônio encontrado pelo UUID, tombamento confere com o snapshot,
  /// unidade de destino resolvida e ativa, e diferente da unidade atual —
  /// pronta para entrar na lista de execução (depende ainda de
  /// confirmação explícita do administrador).
  pronto,

  /// A unidade atual do patrimônio (resolvida pelo UUID) JÁ é a unidade de
  /// destino informada — nada para retificar. Nunca tratado como erro,
  /// só excluído da lista de execução.
  jaNaUnidadeCorreta,

  /// `patrimonioId` da linha não corresponde a nenhum patrimônio
  /// acessível no InvTec — nunca presumido como "não existe no sistema":
  /// pode também ser um patrimônio fora do alcance da permissão atual.
  patrimonioNaoEncontrado,

  /// O `numero_patrimonio` REAL do patrimônio não é equivalente (mesma
  /// regra de zeros à esquerda do resto do app) ao "Tombamento atual no
  /// InvTec" exportado no CSV — o snapshot usado para gerar o plano está
  /// desatualizado para esta linha especificamente. Nunca resolvido
  /// automaticamente: exige revisão manual antes de incluir esta linha.
  tombamentoDivergente,

  /// A unidade atual REAL (resolvida pelo `setor_atual_id` do patrimônio)
  /// não corresponde ao texto "Setor atual (InvTec)" da planilha — mesmo
  /// sinal de snapshot desatualizado que [tombamentoDivergente], mas no
  /// campo de unidade em vez do tombamento.
  setorAtualDivergente,

  /// "Unidade correta (sigla)"/"(nome)" não corresponde a nenhum
  /// [Setor] cadastrado no InvTec — nunca resolvido por aproximação
  /// textual; a unidade precisa ser criada manualmente (tela Setores)
  /// antes desta linha poder ser retificada.
  unidadeDestinoNaoCadastrada,

  /// A unidade de destino foi encontrada, mas está desativada — uma
  /// retificação não pode mover um patrimônio para uma unidade inativa.
  unidadeDestinoInativa,
}

extension ClassificacaoRetificacaoX on ClassificacaoRetificacao {
  /// `true` para qualquer categoria que impede a execução desta linha —
  /// [ClassificacaoRetificacao.jaNaUnidadeCorreta] NÃO é um bloqueio (é só
  /// "nada a fazer"), e [ClassificacaoRetificacao.pronto] obviamente também
  /// não.
  bool get ehBloqueio => this != ClassificacaoRetificacao.pronto && this != ClassificacaoRetificacao.jaNaUnidadeCorreta;
}

/// Resultado da comparação de UMA linha — a linha original, a
/// classificação e, quando [classificacao] é
/// [ClassificacaoRetificacao.pronto]/[ClassificacaoRetificacao.
/// jaNaUnidadeCorreta], os dados já resolvidos (id/nome do setor atual e do
/// setor de destino) necessários para a prévia e para a execução.
class RetificacaoItem {
  const RetificacaoItem({
    required this.linha,
    required this.classificacao,
    this.patrimonioDetalhe,
    this.setorAtualRealId,
    this.setorDestinoId,
    this.setorDestinoNome,
    this.motivoBloqueio,
  });

  final RetificacaoCsvLinha linha;
  final ClassificacaoRetificacao classificacao;

  /// `null` só quando [classificacao] é
  /// [ClassificacaoRetificacao.patrimonioNaoEncontrado].
  final PatrimonioDetalhe? patrimonioDetalhe;

  /// `setor_atual_id` REAL do patrimônio (nunca o texto da planilha) —
  /// preenchido sempre que [patrimonioDetalhe] não é nulo.
  final String? setorAtualRealId;

  /// Preenchido quando a unidade de destino foi resolvida com segurança
  /// (categorias [ClassificacaoRetificacao.pronto]/
  /// [ClassificacaoRetificacao.jaNaUnidadeCorreta]) — nunca em
  /// [ClassificacaoRetificacao.unidadeDestinoNaoCadastrada]/
  /// [ClassificacaoRetificacao.unidadeDestinoInativa].
  final String? setorDestinoId;
  final String? setorDestinoNome;

  /// Explica o bloqueio em texto — sempre preenchido quando
  /// [ClassificacaoRetificacaoX.ehBloqueio] é `true`, nunca um bloqueio
  /// silencioso.
  final String? motivoBloqueio;
}

/// Contagens agregadas de um [RetificacaoLote] — [totalLinhas] é sempre a
/// soma de todas as categorias, nenhuma linha contada duas vezes.
class RetificacaoResumo {
  const RetificacaoResumo({
    required this.totalLinhas,
    required this.prontos,
    required this.jaNaUnidadeCorreta,
    required this.bloqueadosPorMotivo,
  });

  factory RetificacaoResumo.vazio() => const RetificacaoResumo(
    totalLinhas: 0,
    prontos: 0,
    jaNaUnidadeCorreta: 0,
    bloqueadosPorMotivo: {},
  );

  final int totalLinhas;
  final int prontos;
  final int jaNaUnidadeCorreta;

  /// Contagem de bloqueios por categoria — nunca um único número "N
  /// bloqueados" sem dizer por quê.
  final Map<ClassificacaoRetificacao, int> bloqueadosPorMotivo;

  int get totalBloqueados => bloqueadosPorMotivo.values.fold(0, (a, b) => a + b);
}

class RetificacaoLote {
  const RetificacaoLote({required this.itens, required this.resumo});

  final List<RetificacaoItem> itens;
  final RetificacaoResumo resumo;

  /// Só as linhas realmente executáveis — [ClassificacaoRetificacao.
  /// jaNaUnidadeCorreta] e qualquer bloqueio ficam de fora (mas continuam
  /// contados em [resumo] e visíveis em [itens] para a prévia).
  List<RetificacaoItem> get itensProntos =>
      itens.where((i) => i.classificacao == ClassificacaoRetificacao.pronto).toList();
}

/// Motor de comparação — PURO (nenhuma chamada de rede, nenhuma escrita),
/// testável com dados em memória. Resolve cada [RetificacaoCsvLinha] pelo
/// UUID do patrimônio (nunca por número/texto) e valida o tombamento
/// esperado contra o real — nunca presume que o snapshot local ainda
/// reflete o InvTec em produção.
class RetificacaoComparador {
  const RetificacaoComparador._();

  static RetificacaoLote comparar({
    required List<RetificacaoCsvLinha> linhas,
    required Map<String, PatrimonioDetalhe> patrimoniosPorId,
    required List<Setor> setores,
  }) {
    final itens = <RetificacaoItem>[];
    var prontos = 0;
    var jaNaUnidadeCorreta = 0;
    final bloqueadosPorMotivo = <ClassificacaoRetificacao, int>{};

    for (final linha in linhas) {
      final item = _compararLinha(linha, patrimoniosPorId, setores);
      itens.add(item);
      switch (item.classificacao) {
        case ClassificacaoRetificacao.pronto:
          prontos++;
        case ClassificacaoRetificacao.jaNaUnidadeCorreta:
          jaNaUnidadeCorreta++;
        default:
          bloqueadosPorMotivo.update(item.classificacao, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    return RetificacaoLote(
      itens: itens,
      resumo: RetificacaoResumo(
        totalLinhas: linhas.length,
        prontos: prontos,
        jaNaUnidadeCorreta: jaNaUnidadeCorreta,
        bloqueadosPorMotivo: Map.unmodifiable(bloqueadosPorMotivo),
      ),
    );
  }

  static RetificacaoItem _compararLinha(
    RetificacaoCsvLinha linha,
    Map<String, PatrimonioDetalhe> patrimoniosPorId,
    List<Setor> setores,
  ) {
    final detalhe = patrimoniosPorId[linha.patrimonioId];
    if (detalhe == null) {
      return RetificacaoItem(
        linha: linha,
        classificacao: ClassificacaoRetificacao.patrimonioNaoEncontrado,
        motivoBloqueio:
            'Patrimônio ${linha.patrimonioId} não encontrado no InvTec (ou fora do alcance da sua permissão atual).',
      );
    }

    final tombamentoReal = detalhe.patrimonio.numeroPatrimonio;
    if (!tombamentosSaoEquivalentes(tombamentoReal, linha.tombamentoAtualInvtec)) {
      return RetificacaoItem(
        linha: linha,
        classificacao: ClassificacaoRetificacao.tombamentoDivergente,
        patrimonioDetalhe: detalhe,
        setorAtualRealId: detalhe.patrimonio.setorAtualId,
        motivoBloqueio:
            'Tombamento divergente do plano exportado: esperado "${linha.tombamentoAtualInvtec}", '
            'encontrado "${tombamentoReal ?? "(sem tombamento)"}" — revise esta linha individualmente.',
      );
    }

    final setorAtualResolvido = _resolverSetor(
      sigla: linha.setorAtualTexto,
      nome: linha.setorAtualTexto,
      setores: setores,
    );
    if (setorAtualResolvido == null || setorAtualResolvido.id != detalhe.patrimonio.setorAtualId) {
      return RetificacaoItem(
        linha: linha,
        classificacao: ClassificacaoRetificacao.setorAtualDivergente,
        patrimonioDetalhe: detalhe,
        setorAtualRealId: detalhe.patrimonio.setorAtualId,
        motivoBloqueio:
            'Unidade atual divergente do plano exportado: a planilha indica "${linha.setorAtualTexto}", '
            'mas o InvTec mostra "${detalhe.setorNome}" — revise esta linha individualmente.',
      );
    }

    final setorDestino = _resolverSetor(
      sigla: linha.unidadeCorretaSigla,
      nome: linha.unidadeCorretaNome,
      setores: setores,
    );
    if (setorDestino == null) {
      return RetificacaoItem(
        linha: linha,
        classificacao: ClassificacaoRetificacao.unidadeDestinoNaoCadastrada,
        patrimonioDetalhe: detalhe,
        setorAtualRealId: detalhe.patrimonio.setorAtualId,
        motivoBloqueio:
            'Unidade de destino "${linha.unidadeCorretaSigla} — ${linha.unidadeCorretaNome}" não está '
            'cadastrada no InvTec — cadastre-a em Setores antes de retificar esta linha.',
      );
    }
    if (!setorDestino.ativo) {
      return RetificacaoItem(
        linha: linha,
        classificacao: ClassificacaoRetificacao.unidadeDestinoInativa,
        patrimonioDetalhe: detalhe,
        setorAtualRealId: detalhe.patrimonio.setorAtualId,
        setorDestinoId: setorDestino.id,
        setorDestinoNome: setorDestino.nome,
        motivoBloqueio: 'Unidade de destino "${setorDestino.nome}" está desativada no InvTec.',
      );
    }

    if (setorDestino.id == detalhe.patrimonio.setorAtualId) {
      return RetificacaoItem(
        linha: linha,
        classificacao: ClassificacaoRetificacao.jaNaUnidadeCorreta,
        patrimonioDetalhe: detalhe,
        setorAtualRealId: detalhe.patrimonio.setorAtualId,
        setorDestinoId: setorDestino.id,
        setorDestinoNome: setorDestino.nome,
      );
    }

    return RetificacaoItem(
      linha: linha,
      classificacao: ClassificacaoRetificacao.pronto,
      patrimonioDetalhe: detalhe,
      setorAtualRealId: detalhe.patrimonio.setorAtualId,
      setorDestinoId: setorDestino.id,
      setorDestinoNome: setorDestino.nome,
    );
  }

  /// Resolve um [Setor] por sigla (prioridade) ou nome — comparação exata
  /// (trim + maiúsculas), nunca por semelhança/aproximação. `null` quando
  /// nenhum setor cadastrado corresponde.
  static Setor? _resolverSetor({
    required String sigla,
    required String nome,
    required List<Setor> setores,
  }) {
    final siglaNormalizada = sigla.trim().toUpperCase();
    if (siglaNormalizada.isNotEmpty) {
      for (final setor in setores) {
        if ((setor.sigla ?? '').trim().toUpperCase() == siglaNormalizada) return setor;
      }
    }
    final nomeNormalizado = nome.trim().toUpperCase();
    if (nomeNormalizado.isNotEmpty) {
      for (final setor in setores) {
        if (setor.nome.trim().toUpperCase() == nomeNormalizado) return setor;
      }
    }
    return null;
  }
}
