import '../../../../core/errors/app_exception.dart';
import 'patrimonio_comparacao.dart';
import 'patrimonio_decisao.dart';

/// Nome da RPC — usado no texto técnico e no log (mesmo papel de
/// `operacaoConcluirItemSei` em `sei_conclusao_erros.dart`).
const operacaoAplicarDecisaoComparacao = 'aplicar_decisao_comparacao_patrimonio';

/// PROMPT 11.6.5, seção 5 — códigos que o pacote `postgrest` (versão 2.9.1,
/// `lib/src/postgrest_builder.dart`, `_parseResponse`) usa como
/// `PostgrestException.code` quando a resposta NÃO veio do PostgreSQL de
/// verdade: um proxy/gateway devolvendo 502/503/504 (ou 500/408) faz o corpo
/// não ser um JSON de erro do Postgrest válido — `jsonDecode` lança, o catch
/// genérico da biblioteca cria a exceção com `code: '${response.statusCode}'`
/// (o código HTTP cru, como string) em vez de um SQLSTATE real (`P0040`,
/// `42501`, `23505`...). Chamadas RPC são sempre POST, então NUNCA entram no
/// retry automático da biblioteca (`isRetryableMethod` só cobre GET/HEAD) —
/// cada uma dessas falhas chega ao app como uma `PostgrestException` comum,
/// indistinguível de uma recusa real só pelo tipo. Tratar qualquer uma
/// destas como recusa DEFINITIVA seria o erro que a seção 5 descreve
/// explicitamente: "erros de transporte, gateway, timeout... podem
/// representar operações cujo resultado ainda não foi conhecido pelo
/// cliente" — por isso [PatrimonioRepositorySupabase.aplicarDecisaoComparacao]
/// NUNCA envolve um destes códigos em [ComparacaoExecucaoFalhouException]:
/// deixa a exceção passar sem tratamento, para
/// [ComparacaoExecucaoController] classificar como resultado desconhecido
/// (retry seguro, nunca uma nova operação).
bool ehFalhaDeTransporte(String? codigo) => const {'500', '502', '503', '504', '408'}.contains(codigo);

/// PROMPT 11.6.4 — mensagem COMPREENSÍVEL para o usuário de um erro de
/// [operacaoAplicarDecisaoComparacao]. Códigos definidos pela própria RPC:
///  * `P0040` conflito de versão — o patrimônio foi alterado depois da
///    comparação (revalidação da seção 5);
///  * `P0041` `operacao_id` reaproveitado com parâmetros/usuário diferentes;
///  * `P0042` pendência SEI aberta incompatível com a alteração de setor/
///    localização;
///  * `P0043` nenhum campo foi informado (nada para aplicar);
/// mais os já existentes `42501`, `P0001`, `P0002`, `23505` (propagados de
/// `registrar_movimentacao`/da checagem de duplicidade de `patrimonios`).
String mensagemErroExecucaoComparacao({required String? codigo, required String mensagemDoServidor}) {
  if (ehFalhaDeTransporte(codigo)) {
    return 'Não foi possível confirmar se esta alteração chegou a ser aplicada (falha de conexão/tempo limite). '
        'Nada foi presumido: consulte o resultado ou tente novamente — a operação é segura para repetir.';
  }
  switch (codigo) {
    case '42501':
      return 'Você não tem permissão para executar esta alteração.';
    case 'P0002':
      return 'Patrimônio não encontrado. Atualize a comparação e revise novamente.';
    case 'P0040':
      return 'Este patrimônio foi alterado por outra operação desde que a planilha foi comparada. '
          'Nada foi gravado — refaça a comparação para este patrimônio antes de aplicar.';
    case 'P0041':
      return 'Esta operação já havia sido registrada antes com parâmetros diferentes. '
          'Não repita automaticamente: inicie uma nova comparação para este patrimônio.';
    case 'P0042':
      return 'Este patrimônio possui uma pendência SEI em aberto — resolva ou cancele o item SEI antes de '
          'alterar o setor ou a localização por aqui.';
    case 'P0043':
      return 'Nenhum campo foi selecionado para esta alteração.';
    case '23505':
      return 'Já existe outro patrimônio com o número informado.';
    default:
      return 'Não foi possível aplicar esta alteração. Nada foi gravado. '
          'Veja os detalhes técnicos para mais informações.';
  }
}

/// PROMPT 11.6.4 — mesma forma de [SeiEscritaFalhouException]
/// (`lib/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart`):
/// a RPC RECUSOU de forma síncrona — a transação foi desfeita, NADA foi
/// escrito por esta chamada. Qualquer OUTRA exceção (rede/timeout) nunca
/// vira este tipo — ver o comentário de
/// `PatrimonioRepositorySupabase.aplicarDecisaoComparacao`.
class ComparacaoExecucaoFalhouException extends AppException {
  const ComparacaoExecucaoFalhouException({
    required String mensagem,
    this.codigo,
    this.detalhes,
    this.dica,
    super.cause,
  }) : super(mensagem);

  final String? codigo;
  final String? detalhes;
  final String? dica;

  String get textoTecnico {
    final linhas = <String>[
      'Operação: $operacaoAplicarDecisaoComparacao',
      if (codigo != null && codigo!.isNotEmpty) 'Código: $codigo',
      if (message.isNotEmpty) 'Mensagem: $message',
      if (detalhes != null && detalhes!.isNotEmpty) 'Detalhes: $detalhes',
      if (dica != null && dica!.isNotEmpty) 'Dica: $dica',
    ];
    return linhas.join('\n');
  }

  @override
  String toString() => 'ComparacaoExecucaoFalhouException(código: $codigo): $message';
}

ComparacaoExecucaoFalhouException falhaDeExecucaoComparacao({
  required String? codigo,
  required String mensagemDoServidor,
  String? detalhes,
  String? dica,
  Object? cause,
}) {
  return ComparacaoExecucaoFalhouException(
    mensagem: mensagemErroExecucaoComparacao(codigo: codigo, mensagemDoServidor: mensagemDoServidor),
    codigo: codigo,
    detalhes: detalhes,
    dica: dica,
    cause: cause,
  );
}

/// Resultado de UMA chamada bem-sucedida (nova execução OU retry idêntico
/// já registrado — ver [jaExecutado]) de [operacaoAplicarDecisaoComparacao].
class ResultadoAplicacaoDecisao {
  const ResultadoAplicacaoDecisao({
    required this.patrimonioId,
    required this.metadadosAtualizados,
    required this.movimentacaoRegistrada,
    required this.jaExecutado,
    this.movimentacaoId,
    this.concluidoEm,
  });

  factory ResultadoAplicacaoDecisao.fromJson(Map<String, dynamic> json) {
    return ResultadoAplicacaoDecisao(
      patrimonioId: json['patrimonio_id'] as String,
      metadadosAtualizados: json['metadados_atualizados'] as bool? ?? false,
      movimentacaoRegistrada: json['movimentacao_registrada'] as bool? ?? false,
      jaExecutado: json['ja_executado'] as bool? ?? false,
      movimentacaoId: json['movimentacao_id'] as String?,
      concluidoEm: json['concluido_em'] == null ? null : DateTime.parse(json['concluido_em'] as String),
    );
  }

  final String patrimonioId;
  final bool metadadosAtualizados;
  final bool movimentacaoRegistrada;

  /// `true` quando esta chamada não escreveu nada de novo — a RPC encontrou
  /// uma execução anterior com o mesmo `operacao_id` e devolveu o resultado
  /// já gravado (retry seguro após um resultado desconhecido — seção 6).
  final bool jaExecutado;
  final String? movimentacaoId;
  final DateTime? concluidoEm;
}

/// PROMPT 11.6.4 — decisão de UM patrimônio, CONGELADA no momento da
/// confirmação (mesmo espírito de `SeiDecisaoLoteConfirmada`): [operacaoId]
/// é gerado UMA ÚNICA VEZ e nunca recriado, mesmo num retry — é isso que
/// torna reenviar a mesma chamada seguro (idempotência do lado do
/// servidor, ver a migration `aplicar_decisao_comparacao_patrimonio`).
class DecisaoItemParaExecutar {
  const DecisaoItemParaExecutar({
    required this.operacaoId,
    required this.loteId,
    required this.patrimonioId,
    required this.numeroPatrimonio,
    required this.versaoEsperada,
    this.justificativa,
    this.numeroSerie,
    this.marca,
    this.modelo,
    this.descricao,
    this.observacao,
    this.novoSetorId,
    this.novaLocalizacaoId,
  });

  final String operacaoId;
  final String loteId;
  final String patrimonioId;

  /// Só para exibição (progresso, relatório final) — nunca enviado à RPC.
  final String numeroPatrimonio;
  final DateTime versaoEsperada;
  final String? justificativa;
  final String? numeroSerie;
  final String? marca;
  final String? modelo;
  final String? descricao;
  final String? observacao;
  final String? novoSetorId;
  final String? novaLocalizacaoId;

  bool get temMetadado =>
      numeroSerie != null ||
      marca != null ||
      modelo != null ||
      descricao != null ||
      observacao != null;

  bool get temMovimentacao => novoSetorId != null || novaLocalizacaoId != null;
}

/// PROMPT 11.6.4 — traduz [ComparacaoLote] + [decisoes] (estado 100% em
/// memória da tela de revisão, PROMPT 11.6.3) na lista CONGELADA de itens
/// que a execução segura vai enviar, um por patrimônio. PURO (nenhuma
/// chamada de rede/gerador aleatório direto — [gerarOperacaoId] é
/// injetado, mesmo padrão de `gerarLoteId` em `SeiConclusaoLoteController`),
/// testável sem fakes de repositório.
///
/// Um patrimônio só entra na lista quando tem AO MENOS UMA decisão
/// [DecisaoCampoValor.aplicar] (nunca um item 100% ignorado/pendente) — e só
/// os campos com decisão [DecisaoCampoValor.aplicar] entram nos parâmetros
/// (seção 4: "nunca executar atualizações dos campos ignorados"). Itens
/// [ClassificacaoComparacao.bloqueado] ou [ClassificacaoComparacao.novo]
/// NUNCA entram aqui (seção 7: "não cadastrar automaticamente... não
/// incluir os idênticos... " — bloqueados nem têm decisão possível, ver
/// `PatrimonioImportController._campoDivergenteElegiveis`).
///
/// Defesa adicional: uma divergência de setor/localização com decisão
/// "aplicar" mas sem [CampoDivergente.valorPlanilhaId] resolvido (não deve
/// acontecer — [PatrimonioComparador] só cria essas divergências já com o
/// id resolvido) é IGNORADA nesta tradução, nunca aplicada sem o id —
/// nenhuma movimentação é criada por aproximação.
List<DecisaoItemParaExecutar> construirItensParaExecucao({
  required ComparacaoLote comparacao,
  required Map<ChaveDecisaoCampo, DecisaoCampoValor> decisoes,
  required String loteId,
  required String? justificativa,
  required String Function() gerarOperacaoId,
}) {
  final itens = <DecisaoItemParaExecutar>[];

  for (final item in comparacao.itens) {
    if (item.classificacao != ClassificacaoComparacao.divergente) continue;
    final patrimonioId = item.patrimonioId;
    final versao = item.versaoAtualizadoEm;
    if (patrimonioId == null || versao == null) continue;

    String? numeroSerie;
    String? marca;
    String? modelo;
    String? descricao;
    String? observacao;
    String? novoSetorId;
    String? novaLocalizacaoId;
    var temAoMenosUmaAplicacao = false;

    for (final campo in item.divergencias) {
      final decisao = decisoes[ChaveDecisaoCampo(patrimonioId: patrimonioId, campo: campo.campo)] ?? DecisaoCampoValor.pendente;
      if (decisao != DecisaoCampoValor.aplicar) continue;

      switch (campo.campo) {
        case 'Descrição':
          descricao = campo.valorPlanilha;
          temAoMenosUmaAplicacao = true;
        case 'Marca':
          marca = campo.valorPlanilha;
          temAoMenosUmaAplicacao = true;
        case 'Modelo':
          modelo = campo.valorPlanilha;
          temAoMenosUmaAplicacao = true;
        case 'Número de série':
          numeroSerie = campo.valorPlanilha;
          temAoMenosUmaAplicacao = true;
        case 'Observação':
          observacao = campo.valorPlanilha;
          temAoMenosUmaAplicacao = true;
        case 'Setor atual':
          if (campo.valorPlanilhaId != null) {
            novoSetorId = campo.valorPlanilhaId;
            temAoMenosUmaAplicacao = true;
          }
        case 'Localização atual':
          if (campo.valorPlanilhaId != null) {
            novaLocalizacaoId = campo.valorPlanilhaId;
            temAoMenosUmaAplicacao = true;
          }
      }
    }

    if (!temAoMenosUmaAplicacao) continue;

    itens.add(
      DecisaoItemParaExecutar(
        operacaoId: gerarOperacaoId(),
        loteId: loteId,
        patrimonioId: patrimonioId,
        numeroPatrimonio: item.numeroPatrimonio ?? '',
        versaoEsperada: versao,
        justificativa: justificativa,
        numeroSerie: numeroSerie,
        marca: marca,
        modelo: modelo,
        descricao: descricao,
        observacao: observacao,
        novoSetorId: novoSetorId,
        novaLocalizacaoId: novaLocalizacaoId,
      ),
    );
  }

  return itens;
}
