import '../domain/sei_decisao_campo.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_item_pendencia_status.dart';
import '../domain/sei_item_pendente.dart';

/// Regras de negócio puras sobre um [SeiDocumentoPendente] já persistido —
/// sem I/O, nunca chamam o repositório; usadas pela UI para decidir o que
/// mostrar habilitado/desabilitado, e reproduzidas (não apenas checadas na
/// UI) pelas funções SECURITY DEFINER da migration, que são a autoridade
/// final.

/// Só um item PENDENTE pode ser cancelado; nunca desfaz uma conclusão nem
/// um cancelamento anterior.
bool itemPodeSerCancelado(SeiItemPendente item) => item.status == SeiItemPendenciaStatus.pendente;

/// só um item PENDENTE oferece "Concluir entrega" (nunca um
/// CANCELADO nem um CONCLUIDO). A permissão do usuário (ADMIN/GESTOR/
/// OPERADOR) é decidida à parte, pela tela. Um item pendente que ainda não
/// atende às pré-condições técnicas abre a confirmação mesmo assim: ela lista
/// os motivos do bloqueio em vez de esconder a ação.
bool itemPodeSerConcluido(SeiItemPendente item) => item.status == SeiItemPendenciaStatus.pendente;

/// Pré-condições técnicas para um item poder vir a ser concluído: precisa
/// estar PENDENTE, ter um patrimônio resolvido, ter um setor de destino
/// resolvido, e ambas as decisões de localização/responsável já terem sido
/// tomadas (nunca `pendente` — a autorização geral do documento não
/// resolve isso).
bool itemElegivelParaConclusaoFutura(SeiItemPendente item) {
  if (item.status != SeiItemPendenciaStatus.pendente) return false;
  if (item.patrimonioId == null) return false;
  if (item.destinoSetorId == null) return false;
  if (item.decisaoLocalizacao == SeiDecisaoCampo.pendente) return false;
  if (item.decisaoResponsavel == SeiDecisaoCampo.pendente) return false;
  return true;
}

/// "Concluir todos os pendentes elegíveis" nunca inclui itens cancelados ou
/// bloqueados (aqui, "bloqueado" = tecnicamente não elegível pelas regras
/// acima) — precisa ser filtrado explicitamente, nunca presumido a partir
/// de "todo item que não está concluído".
List<SeiItemPendente> itensElegiveisParaConclusaoFutura(List<SeiItemPendente> itens) =>
    itens.where(itemElegivelParaConclusaoFutura).toList();

/// as MESMAS checagens de [itemElegivelParaConclusaoFutura],
/// uma a uma, devolvendo o(s) motivo(s) específico(s) pelo(s) qual(is)
/// [item] NÃO é elegível. Usada por "Concluir todos os aptos"
/// (`sei_selecao_aptos_lote.dart`) para nunca excluir um item da tela sem
/// explicação — a lista de não incluídos sempre vem acompanhada do motivo,
/// nunca só desaparece. Lista vazia == elegível (mesmo resultado de
/// [itemElegivelParaConclusaoFutura]).
List<String> motivosNaoElegivelParaConclusaoFutura(SeiItemPendente item) {
  final motivos = <String>[];
  if (item.status != SeiItemPendenciaStatus.pendente) {
    motivos.add('Não está PENDENTE (está ${item.status.label}).');
  }
  if (item.patrimonioId == null) {
    motivos.add('Não está vinculado a um patrimônio — corrija o número do patrimônio pela edição do documento.');
  }
  if (item.destinoSetorId == null) {
    motivos.add('O setor de destino ainda não foi definido — corrija pela edição do documento.');
  }
  if (item.decisaoLocalizacao == SeiDecisaoCampo.pendente) {
    motivos.add('A decisão sobre a localização de destino ainda está pendente — defina pela edição do documento.');
  }
  if (item.decisaoResponsavel == SeiDecisaoCampo.pendente) {
    motivos.add('A decisão sobre o responsável de destino ainda está pendente — defina pela edição do documento.');
  }
  return motivos;
}

/// Replica, no cliente, a mesma regra aplicada no banco: o documento
/// (dados principais e itens) só pode ser editado enquanto nenhum item
/// estiver concluído. Usada só para habilitar/desabilitar a UI — a fonte
/// de verdade real é a checagem dentro de `editar_documento_sei_pendente`
/// no banco, nunca este cálculo no cliente sozinho.
///
/// Um documento ENCERRADO (0 itens pendentes) também não é mais editável,
/// mesmo sem nenhum item concluído.
bool documentoPodeSerEditado(SeiDocumentoPendente documento) => documento.permiteEdicao;
