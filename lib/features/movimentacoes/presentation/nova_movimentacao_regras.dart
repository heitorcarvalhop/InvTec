import '../../patrimonios/domain/patrimonio.dart';
import '../domain/movimentacao.dart';

/// Regras de UX para o formulário de Nova Movimentação (PROMPT 10.2) —
/// espelham a matriz de transição e a tabela "Regras por tipo" documentadas
/// em docs/database.md, só para adaptar QUAIS campos o formulário mostra e
/// habilita. Isto é só conveniência de interface: a RPC `registrar_movimentacao`
/// é quem valida de verdade (ver seção 16 do prompt — "Flutter = UX, RPC =
/// autoridade") e pode rejeitar mesmo algo que passou por aqui (ex.: um
/// setor foi desativado por outra sessão entre a abertura do formulário e a
/// confirmação).

/// Tipos oferecidos para o status atual do patrimônio, na ordem em que
/// aparecem no seletor — mesma matriz de docs/database.md ("Matriz de
/// transição"). BAIXADO só oferece AJUSTE_INVENTARIO (única movimentação
/// aceita depois da baixa).
List<MovimentacaoTipo> tiposCompativeisComStatus(PatrimonioStatus status) {
  switch (status) {
    case PatrimonioStatus.disponivel:
    case PatrimonioStatus.emUso:
      return const [
        MovimentacaoTipo.entrada,
        MovimentacaoTipo.saida,
        MovimentacaoTipo.transferencia,
        MovimentacaoTipo.emprestimo,
        MovimentacaoTipo.manutencao,
        MovimentacaoTipo.alteracaoResponsavel,
        MovimentacaoTipo.ajusteInventario,
        MovimentacaoTipo.baixa,
      ];
    case PatrimonioStatus.emprestado:
      return const [MovimentacaoTipo.devolucao, MovimentacaoTipo.ajusteInventario, MovimentacaoTipo.baixa];
    case PatrimonioStatus.emManutencao:
      return const [
        MovimentacaoTipo.retornoManutencao,
        MovimentacaoTipo.ajusteInventario,
        MovimentacaoTipo.baixa,
      ];
    case PatrimonioStatus.baixado:
      return const [MovimentacaoTipo.ajusteInventario];
  }
}

/// `destino_id` é obrigatório para estes tipos — "deslocamento físico" ou
/// TRANSFERENCIA (que também aceita o próprio setor atual, para o cenário
/// "movimentação interna").
bool tipoExigeDestino(MovimentacaoTipo tipo) {
  switch (tipo) {
    case MovimentacaoTipo.entrada:
    case MovimentacaoTipo.saida:
    case MovimentacaoTipo.transferencia:
    case MovimentacaoTipo.emprestimo:
    case MovimentacaoTipo.devolucao:
    case MovimentacaoTipo.manutencao:
    case MovimentacaoTipo.retornoManutencao:
      return true;
    case MovimentacaoTipo.baixa:
    case MovimentacaoTipo.ajusteInventario:
    case MovimentacaoTipo.alteracaoResponsavel:
      return false;
  }
}

/// `destino_id` é proibido (a RPC rejeita se vier preenchido).
bool tipoProibeDestino(MovimentacaoTipo tipo) =>
    tipo == MovimentacaoTipo.baixa || tipo == MovimentacaoTipo.alteracaoResponsavel;

/// A RPC real (PROMPT 10.2.2, seção 3 — auditada em produção) rejeita
/// `destino_id = setor_atual_id` para estes seis tipos ("deslocamento
/// físico" clássico): "Destino igual ao setor atual do patrimônio não é
/// permitido para %". TRANSFERENCIA é a ÚNICA exceção — para ela o mesmo
/// setor atual é a forma explícita de pedir "movimentação interna", nunca
/// um erro.
bool tipoExigeDestinoDiferente(MovimentacaoTipo tipo) {
  switch (tipo) {
    case MovimentacaoTipo.entrada:
    case MovimentacaoTipo.saida:
    case MovimentacaoTipo.emprestimo:
    case MovimentacaoTipo.devolucao:
    case MovimentacaoTipo.manutencao:
    case MovimentacaoTipo.retornoManutencao:
      return true;
    case MovimentacaoTipo.transferencia:
    case MovimentacaoTipo.baixa:
    case MovimentacaoTipo.ajusteInventario:
    case MovimentacaoTipo.alteracaoResponsavel:
      return false;
  }
}

/// AJUSTE_INVENTARIO aceita destino opcional (para corrigir o setor sem
/// mudar de tipo de movimentação) — nem obrigatório nem proibido.
bool tipoDestinoOpcional(MovimentacaoTipo tipo) => tipo == MovimentacaoTipo.ajusteInventario;

/// `responsavel_destino` obrigatório e diferente do atual.
bool tipoExigeResponsavel(MovimentacaoTipo tipo) =>
    tipo == MovimentacaoTipo.emprestimo || tipo == MovimentacaoTipo.alteracaoResponsavel;

/// `responsavel_destino` proibido (a RPC rejeita se vier preenchido).
bool tipoProibeResponsavel(MovimentacaoTipo tipo) =>
    tipo == MovimentacaoTipo.baixa || tipo == MovimentacaoTipo.ajusteInventario;

/// Campo de localização de destino faz sentido para este tipo (mesmo que
/// opcional) — BAIXA e ALTERACAO_RESPONSAVEL não têm nenhum conceito de
/// destino, físico ou não.
bool tipoPermiteLocalizacao(MovimentacaoTipo tipo) =>
    !tipoProibeDestino(tipo);

/// Só AJUSTE_INVENTARIO aceita `p_limpar_localizacao` — qualquer outro tipo
/// é rejeitado pela RPC se enviado.
bool tipoPermiteLimparLocalizacao(MovimentacaoTipo tipo) => tipo == MovimentacaoTipo.ajusteInventario;

/// TRANSFERENCIA com destino = setor atual é a "movimentação interna"
/// (muda só a localização dentro da mesma gerência) — é o cliente que
/// decide o rótulo, comparando destino com o setor atual (ver
/// docs/database.md, "TRANSFERENCIA não ganhou um novo valor de enum").
bool ehTransferenciaInterna({
  required MovimentacaoTipo tipo,
  required String? destinoId,
  required String setorAtualId,
}) {
  return tipo == MovimentacaoTipo.transferencia && destinoId != null && destinoId == setorAtualId;
}

/// Para AJUSTE_INVENTARIO: o setor de destino escolhido é DIFERENTE do
/// setor atual do patrimônio (nunca `true` para "Manter o setor atual", que
/// chega aqui como `destinoId == null`, nem para um `destinoId` que por
/// acaso seja igual ao atual). Decide entre os dois modos visuais do campo
/// de localização (PROMPT 10.2.2, seção 5): "Manter/Definir/Limpar" quando
/// o setor não muda, ou "Selecionar localização do novo setor/Não informar
/// localização" quando muda — nunca oferece "Manter" depois de trocar de
/// setor, porque não há mais o que preservar.
bool ajusteInventarioTrocouSetor({required String? destinoId, required String setorAtualId}) {
  return destinoId != null && destinoId != setorAtualId;
}
