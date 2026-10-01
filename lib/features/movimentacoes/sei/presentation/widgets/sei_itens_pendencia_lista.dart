import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/setor_display.dart';
import '../../../../../core/widgets/setor_compact_text.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../application/sei_pendencia_regras.dart';
import '../../domain/sei_documento_pendente.dart';
import '../../domain/sei_item_pendencia_status.dart';
import '../../domain/sei_item_pendente.dart';
import '../../domain/sei_valor_corrigivel.dart';
import '../sei_situacao_visual.dart';

/// Abaixo desta largura (diálogo em tela estreita/Android) cada item vira um
/// bloco de várias linhas em vez de uma linha de colunas.
const double _larguraMinimaLinha = 640;

const double _larguraColunaLinha = 52;
const double _larguraColunaStatus = 132;
const double _larguraColunaAcao = 224;

// Patrimônio nunca deve ficar abaixo de flex:5 — a coluna mostra o número
// de patrimônio em negrito, não só um rótulo, e trunca fácil se encolher.
// Origem→Destino cede espaço primeiro (já usa reticências + tooltip).
// Soma continua 16; colunas de largura FIXA nunca mudam.
const int _flexColunaPatrimonio = 5;
const int _flexColunaChamado = 5;
const int _flexColunaOrigemDestino = 6;

/// largura fixa da coluna de seleção em lote (checkbox),
/// mesmo padrão das demais colunas de largura fixa desta lista.
const double _larguraColunaSelecao = 40;

/// Itens de um Documento SEI pendente, dentro do diálogo de detalhe.
///
/// Cada item é UMA linha compacta; status e ação "Cancelar" têm largura FIXA
/// e nunca dependem de rolagem horizontal — só os textos longos (origem →
/// destino) cedem, com reticências e tooltip. Clicar na linha expande a
/// ficha completa do item.
///
/// Só apresentação: [onCancelarItem] é o mesmo callback de antes, e o botão
/// só aparece para item PENDENTE quando [podeGerenciar] (mesma regra —
/// `itemPodeSerCancelado`); cancelar um item nunca cancela os demais.
class SeiItensPendenciaLista extends StatelessWidget {
  const SeiItensPendenciaLista({
    super.key,
    required this.documento,
    required this.podeGerenciar,
    required this.onCancelarItem,
    this.onConcluirItem,
    this.selecionados = const {},
    this.onAlternarSelecao,
  });

  final SeiDocumentoPendente documento;
  final bool podeGerenciar;
  final ValueChanged<String> onCancelarItem;

  /// "Concluir entrega" de um item. `null` esconde a ação.
  /// O botão só aparece para item PENDENTE quando [podeGerenciar] (ADMIN/
  /// GESTOR/OPERADOR): nunca para CANCELADO, CONCLUIDO nem CONSULTA, e nunca
  /// no lugar de "Cancelar" — são duas ações separadas.
  final ValueChanged<String>? onConcluirItem;

  /// seleção em LOTE, CONTROLADA pelo diálogo pai
  /// (`SeiPendenciaDetalheDialog`) e identificada pelos ids dos itens; esta
  /// lista nunca guarda o próprio estado de seleção. `onAlternarSelecao`
  /// `null` esconde a coluna de checkbox inteira (mesmo padrão de
  /// [onConcluirItem] — recurso opcional). O checkbox só aparece para item
  /// PENDENTE quando [podeGerenciar] (mesma regra de [onConcluirItem]:
  /// itens CONCLUÍDOS/CANCELADOS nunca podem ser enviados à RPC de lote).
  final Set<String> selecionados;
  final ValueChanged<String>? onAlternarSelecao;

  @override
  Widget build(BuildContext context) {
    final itens = documento.itens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < _larguraMinimaLinha;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compacto) ...[_Cabecalho(mostrarSelecao: onAlternarSelecao != null), const Divider(height: 1)],
            for (var i = 0; i < itens.length; i++) ...[
              _ItemLinha(
                item: itens[i],
                compacto: compacto,
                podeCancelar: podeGerenciar && itemPodeSerCancelado(itens[i]),
                onCancelar: () => onCancelarItem(itens[i].id),
                podeConcluir: podeGerenciar && onConcluirItem != null && itemPodeSerConcluido(itens[i]),
                onConcluir: () => onConcluirItem?.call(itens[i].id),
                mostrarColunaSelecao: onAlternarSelecao != null,
                podeSelecionar: podeGerenciar && onAlternarSelecao != null && itemPodeSerConcluido(itens[i]),
                selecionado: selecionados.contains(itens[i].id),
                onAlternarSelecao: () => onAlternarSelecao?.call(itens[i].id),
              ),
              if (i < itens.length - 1) const Divider(height: 1),
            ],
          ],
        );
      },
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.mostrarSelecao});

  final bool mostrarSelecao;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.label(context);
    Widget cabecalho(String texto) => Text(texto, style: style, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false);
    return Container(
      color: Theme.of(context).surfaceColors.tableHeader,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Row(
        children: [
          // Sem "selecionar todos" aqui de propósito: "todo pendente" e "todo
          // apto" são conjuntos diferentes; "Concluir todos os aptos" é uma
          // ação separada, fora desta lista.
          if (mostrarSelecao) const SizedBox(width: _larguraColunaSelecao),
          SizedBox(
            width: _larguraColunaLinha,
            child: cabecalho('Linha'),
          ),
          Expanded(
            flex: _flexColunaPatrimonio,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: cabecalho('Patrimônio'),
            ),
          ),
          Expanded(
            flex: _flexColunaChamado,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: cabecalho('Chamado'),
            ),
          ),
          Expanded(
            flex: _flexColunaOrigemDestino,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: cabecalho('Origem → Destino'),
            ),
          ),
          SizedBox(
            width: _larguraColunaStatus,
            child: cabecalho('Status'),
          ),
          SizedBox(
            width: _larguraColunaAcao,
            child: cabecalho('Ação'),
          ),
        ],
      ),
    );
  }
}

class _ItemLinha extends StatefulWidget {
  const _ItemLinha({
    required this.item,
    required this.compacto,
    required this.podeCancelar,
    required this.onCancelar,
    required this.podeConcluir,
    required this.onConcluir,
    required this.mostrarColunaSelecao,
    required this.podeSelecionar,
    required this.selecionado,
    required this.onAlternarSelecao,
  });

  final SeiItemPendente item;
  final bool compacto;
  final bool podeCancelar;
  final VoidCallback onCancelar;
  final bool podeConcluir;
  final VoidCallback onConcluir;

  /// `true` quando a lista INTEIRA está em modo de seleção
  /// (reserva o espaço da coluna, mesmo padrão de [_Cabecalho.mostrarSelecao]
  /// — a coluna nunca "pula" de largura entre linhas). [podeSelecionar] é
  /// por ITEM (`false` some com o checkbox — item não PENDENTE, ou sem
  /// permissão — nunca desenhado desabilitado, para não sugerir que dá para
  /// tentar mesmo assim).
  final bool mostrarColunaSelecao;
  final bool podeSelecionar;
  final bool selecionado;
  final VoidCallback onAlternarSelecao;

  @override
  State<_ItemLinha> createState() => _ItemLinhaState();
}

class _ItemLinhaState extends State<_ItemLinha> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expandido = !_expandido),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: widget.compacto ? _conteudoCompacto(context, item) : _conteudoLinha(context, item),
          ),
        ),
        if (_expandido) _FichaDoItem(item: item),
      ],
    );
  }

  Widget _conteudoLinha(BuildContext context, SeiItemPendente item) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          if (widget.mostrarColunaSelecao)
            SizedBox(
              width: _larguraColunaSelecao,
              child: widget.podeSelecionar
                  ? Checkbox(
                      key: Key('sei-item-selecao-${item.id}'),
                      value: widget.selecionado,
                      onChanged: (_) => widget.onAlternarSelecao(),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )
                  : null,
            ),
          SizedBox(
            width: _larguraColunaLinha,
            child: Row(
              children: [
                Icon(_expandido ? Icons.expand_less : Icons.expand_more, size: 18),
                const SizedBox(width: 2),
                Text('${item.linha}', style: AppTypography.body(context)),
              ],
            ),
          ),
          Expanded(
            flex: _flexColunaPatrimonio,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: _CelulaPatrimonio(item: item),
            ),
          ),
          Expanded(
            flex: _flexColunaChamado,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: _TextoUmaLinha(item.numeroChamado.valorEfetivo ?? '—'),
            ),
          ),
          Expanded(
            flex: _flexColunaOrigemDestino,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: _OrigemDestino(item: item),
            ),
          ),
          SizedBox(
            width: _larguraColunaStatus,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _StatusItemChip(item: item),
            ),
          ),
          SizedBox(
            width: _larguraColunaAcao,
            child: (widget.podeConcluir || widget.podeCancelar)
                ? _AcoesDoItem(
                    podeConcluir: widget.podeConcluir,
                    onConcluir: widget.onConcluir,
                    podeCancelar: widget.podeCancelar,
                    onCancelar: widget.onCancelar,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _conteudoCompacto(BuildContext context, SeiItemPendente item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkbox em linha própria, antes do resumo: a linha de resumo já
        // fica rente ao limite em telas estreitas (Android 360px), então
        // largura extra ali estoura.
        if (widget.mostrarColunaSelecao && widget.podeSelecionar)
          Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: 'Selecionar para conclusão em lote',
              child: Checkbox(
                key: Key('sei-item-selecao-${item.id}'),
                value: widget.selecionado,
                onChanged: (_) => widget.onAlternarSelecao(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        Row(
          children: [
            Icon(_expandido ? Icons.expand_less : Icons.expand_more, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text('#${item.linha}', style: AppTypography.auxiliary(context)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _CelulaPatrimonio(item: item)),
            const SizedBox(width: AppSpacing.sm),
            _StatusItemChip(item: item),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 26, top: AppSpacing.xs),
          child: _OrigemDestino(item: item),
        ),
        if (widget.podeConcluir || widget.podeCancelar)
          Align(
            alignment: Alignment.centerRight,
            child: _AcoesDoItem(
              podeConcluir: widget.podeConcluir,
              onConcluir: widget.onConcluir,
              podeCancelar: widget.podeCancelar,
              onCancelar: widget.onCancelar,
            ),
          ),
      ],
    );
  }
}

/// As duas ações do item, SEPARADAS e lado a lado (quebram de linha se
/// faltar largura, nunca cortam): "Concluir entrega" (registra uma
/// movimentação real, depois de uma confirmação) e "Cancelar".
class _AcoesDoItem extends StatelessWidget {
  const _AcoesDoItem({
    required this.podeConcluir,
    required this.onConcluir,
    required this.podeCancelar,
    required this.onCancelar,
  });

  final bool podeConcluir;
  final VoidCallback onConcluir;
  final bool podeCancelar;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (podeConcluir)
          Tooltip(
            message: 'Confirmar a entrega física e registrar a movimentação deste item',
            child: FilledButton.tonal(
              onPressed: onConcluir,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Concluir entrega'),
            ),
          ),
        if (podeCancelar) _BotaoCancelar(onPressed: onCancelar),
      ],
    );
  }
}

class _BotaoCancelar extends StatelessWidget {
  const _BotaoCancelar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cancelar somente este item',
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: const Text('Cancelar'),
      ),
    );
  }
}

/// Número do patrimônio (efetivo: corrigido ?? original) em destaque, com o
/// equipamento persistido no documento logo abaixo — nunca inventado: sem
/// `equipamentoTexto`, só o número. Um ícone discreto avisa que há dado
/// corrigido (os originais aparecem na ficha expandida).
class _CelulaPatrimonio extends StatelessWidget {
  const _CelulaPatrimonio({required this.item});

  final SeiItemPendente item;

  @override
  Widget build(BuildContext context) {
    final equipamento = item.equipamentoTexto.valorEfetivo;
    final temEquipamento = equipamento != null && equipamento.isNotEmpty;
    return Row(
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TextoUmaLinha(item.numeroPatrimonio.valorEfetivo ?? '—', negrito: true),
              if (temEquipamento) _TextoUmaLinha(equipamento, secundario: true),
            ],
          ),
        ),
        if (_temCorrecao(item))
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xs),
            child: Tooltip(
              message: 'Contém dados corrigidos — veja a ficha do item',
              child: Icon(Icons.edit_note, size: 16),
            ),
          ),
      ],
    );
  }
}

class _OrigemDestino extends StatelessWidget {
  const _OrigemDestino({required this.item});

  final SeiItemPendente item;

  @override
  Widget build(BuildContext context) {
    final estilo = AppTypography.body(context);
    Widget lado(String? nome, String? sigla, SeiValorCorrigivel<String> texto) {
      if (nome == null) return _TextoUmaLinha(texto.valorEfetivo ?? '—');
      return SetorCompactText(nome: nome, sigla: sigla, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo);
    }

    return Row(
      children: [
        Flexible(child: lado(item.origemSetorNome, item.origemSetorSigla, item.origemTexto)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Icon(Icons.arrow_forward, size: 16),
        ),
        Flexible(child: lado(item.destinoSetorNome, item.destinoSetorSigla, item.destinoTexto)),
      ],
    );
  }
}

class _TextoUmaLinha extends StatelessWidget {
  const _TextoUmaLinha(this.texto, {this.negrito = false, this.secundario = false});

  final String texto;
  final bool negrito;
  final bool secundario;

  @override
  Widget build(BuildContext context) {
    var estilo = secundario ? AppTypography.auxiliary(context) : AppTypography.body(context);
    if (negrito) estilo = estilo?.copyWith(fontWeight: FontWeight.w700);
    return Tooltip(
      message: texto,
      child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo),
    );
  }
}

class _StatusItemChip extends StatelessWidget {
  const _StatusItemChip({required this.item});

  final SeiItemPendente item;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDoStatusItemPendencia(item.status);
    return StatusChip(label: item.status.label, kind: kind, icon: icon);
  }
}

bool _temCorrecao(SeiItemPendente item) =>
    item.numeroPatrimonio.foiCorrigido ||
    item.destinoTexto.foiCorrigido ||
    item.numeroChamado.foiCorrigido ||
    item.equipamentoTexto.foiCorrigido;

/// Ficha completa do item (aberta ao clicar na linha): tudo que a linha
/// compacta não mostra — equipamento, chamado, setores por extenso, situação,
/// motivo de cancelamento, localização/responsável de destino e, para cada
/// dado corrigido, o valor ORIGINAL do PDF ao lado do corrigido.
class _FichaDoItem extends StatelessWidget {
  const _FichaDoItem({required this.item});

  final SeiItemPendente item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origem = siglaOuNomeSetor(sigla: item.origemSetorSigla, nome: item.origemSetorNome);
    final destino = siglaOuNomeSetor(sigla: item.destinoSetorSigla, nome: item.destinoSetorNome);

    final campos = <(String, String)>[
      ('Patrimônio', item.numeroPatrimonio.valorEfetivo ?? '—'),
      ('Equipamento', item.equipamentoTexto.valorEfetivo ?? '—'),
      ('Chamado', item.numeroChamado.valorEfetivo ?? '—'),
      ('Origem', _setorPorExtenso(item.origemSetorNome, origem, item.origemTexto.valorEfetivo)),
      ('Destino', _setorPorExtenso(item.destinoSetorNome, destino, item.destinoTexto.valorEfetivo)),
      ('Situação', item.status.label),
      if (item.localizacaoDestinoNome != null) ('Localização de destino', item.localizacaoDestinoNome!),
      if (item.responsavelDestino != null && item.responsavelDestino!.isNotEmpty)
        ('Responsável de destino', item.responsavelDestino!),
      if (item.motivoCancelamento != null && item.motivoCancelamento!.isNotEmpty)
        ('Motivo do cancelamento', item.motivoCancelamento!),
      if (item.movimentacaoId != null) ('Movimentação registrada', item.movimentacaoId!),
    ];

    final correcoes = <(String, SeiValorCorrigivel<String>)>[
      ('Patrimônio', item.numeroPatrimonio),
      ('Equipamento', item.equipamentoTexto),
      ('Chamado', item.numeroChamado),
      ('Destino', item.destinoTexto),
    ].where((c) => c.$2.foiCorrigido).toList();

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (rotulo, valor) in campos)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(rotulo, style: AppTypography.auxiliary(context)),
                      Text(valor, style: AppTypography.body(context)),
                    ],
                  ),
                ),
            ],
          ),
          if (correcoes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Dados corrigidos', style: AppTypography.label(context)),
            for (final (rotulo, valor) in correcoes)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$rotulo: original "${valor.original ?? '—'}" → corrigido "${valor.corrigido}"'
                  '${valor.corrigidoPorNome != null ? ' (por ${valor.corrigidoPorNome})' : ''}'
                  '${valor.motivoCorrecao != null ? ' — ${valor.motivoCorrecao}' : ''}',
                  style: AppTypography.body(context),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "GETEC — Gerência de Tecnologia" quando há sigla e nome; só o nome ou o
/// texto lido do PDF nos demais casos.
String _setorPorExtenso(String? nome, String? compacto, String? textoDoPdf) {
  if (nome == null) return textoDoPdf ?? '—';
  if (compacto == null || compacto == nome) return nome;
  return '$compacto — $nome';
}
