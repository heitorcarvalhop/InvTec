import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../localizacoes/data/localizacao_repository_supabase.dart';
import '../../../../setores/domain/setor.dart';
import '../../../presentation/movimentacoes_reference_data.dart';
import '../../application/sei_evento_diff.dart';
import '../../data/documentos_sei_repository_supabase.dart';
import '../../domain/sei_documento_pendente.dart';
import '../../domain/sei_evento_documento.dart';

/// "Histórico de alterações" de um Documento SEI pendente — lê a auditoria
/// gravada em `documentos_sei_eventos` via
/// `DocumentosSeiRepository.listarEventos`. Só leitura: a policy de SELECT
/// já cobre todos os perfis e nenhuma policy de escrita concede
/// INSERT/UPDATE/DELETE, então o widget não precisa de checagem de
/// permissão adicional.
class SeiHistoricoAlteracoes extends ConsumerWidget {
  const SeiHistoricoAlteracoes({super.key, required this.documento});

  final SeiDocumentoPendente documento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventosAsync = ref.watch(_eventosDocumentoProvider(documento.id));

    return eventosAsync.when(
      data: (eventos) {
        if (eventos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('Nenhum evento registrado para este documento ainda.', style: AppTypography.auxiliary(context)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < eventos.length; i++) ...[
              if (i > 0) const Divider(height: AppSpacing.lg),
              _EventoTile(evento: eventos[i], documento: documento),
            ],
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text('Não foi possível carregar o histórico de alterações.', style: AppTypography.auxiliary(context)),
      ),
    );
  }
}

final _eventosDocumentoProvider = FutureProvider.autoDispose.family<List<SeiEventoDocumento>, String>((
  ref,
  documentoId,
) {
  return ref.watch(documentosSeiRepositoryProvider).listarEventos(documentoId);
});

class _EventoTile extends StatelessWidget {
  const _EventoTile({required this.evento, required this.documento});

  final SeiEventoDocumento evento;
  final SeiDocumentoPendente documento;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icone, rotuloTipo) = _visualDoTipo(evento.tipo);
    final diffDocumento = diffDocumentoDoEvento(evento.dadosAntes, evento.dadosDepois);
    final diffItens = diffItensDoEvento(evento.dadosAntes, evento.dadosDepois);
    final temDiff = diffDocumento.isNotEmpty || diffItens.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(rotuloTipo, style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(_formatarDataHora(evento.criadoEm), style: AppTypography.caption(context)),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Usuário: ${evento.autorNome}', style: AppTypography.auxiliary(context)),
                if (evento.tipo == SeiTipoEventoDocumento.itemCancelado) ...[
                  const SizedBox(height: 4),
                  Text(_rotuloItemCancelado(evento, documento), style: AppTypography.body(context)),
                ],
                if (evento.tipo == SeiTipoEventoDocumento.itemConcluido) ...[
                  const SizedBox(height: 4),
                  _DetalhesDaConclusao(evento: evento, documento: documento),
                ],
                if (temDiff) ...[
                  const SizedBox(height: AppSpacing.sm),
                  for (final campo in diffDocumento) _LinhaCampoAlterado(campo: campo),
                  for (final item in diffItens) ...[
                    if (diffItens.first != item) const SizedBox(height: AppSpacing.sm),
                    Text(item.rotuloItem, style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w600)),
                    for (final campo in item.campos) _LinhaCampoAlterado(campo: campo),
                  ],
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(_rotuloDescricao(evento.tipo), style: AppTypography.auxiliary(context)),
                Text(evento.descricao, style: AppTypography.body(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// o que um evento ITEM_CONCLUIDO registrou (gravado por
/// `concluir_item_documento_sei`): o patrimônio, a movimentação criada e o
/// trajeto origem → destino. Só LÊ `dados_depois`; um campo ausente (evento
/// mais antigo/de outro formato) simplesmente não é mostrado.
class _DetalhesDaConclusao extends StatelessWidget {
  const _DetalhesDaConclusao({required this.evento, required this.documento});

  final SeiEventoDocumento evento;
  final SeiDocumentoPendente documento;

  @override
  Widget build(BuildContext context) {
    final depois = evento.dadosDepois;
    final movimentacaoId = depois?['movimentacao_id'] as String?;
    final movimentacao = depois?['movimentacao'] as Map<String, dynamic>?;
    final origemId = movimentacao?['origem_id'] as String?;
    final destinoId = movimentacao?['destino_id'] as String?;
    final localizacaoId = movimentacao?['localizacao_destino_id'] as String?;
    final responsavel = movimentacao == null ? null : (movimentacao['responsavel_destino'] as String?);
    final estilo = AppTypography.body(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_rotuloItemConcluido(evento, documento), style: estilo),
        if (movimentacaoId != null)
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              Text('Movimentação criada:', style: AppTypography.auxiliary(context)),
              SelectableText(movimentacaoId, style: estilo),
            ],
          ),
        if (origemId != null || destinoId != null)
          Wrap(
            spacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Origem → Destino:', style: AppTypography.auxiliary(context)),
              _ValorCampoEvento(chave: 'destino_setor_id', valor: origemId),
              Text('→', style: estilo),
              _ValorCampoEvento(chave: 'destino_setor_id', valor: destinoId),
            ],
          ),
        if (movimentacao != null)
          Wrap(
            spacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Localização de destino:', style: AppTypography.auxiliary(context)),
              if (localizacaoId == null)
                Text('Não informado', style: estilo)
              else
                _ValorCampoEvento(chave: 'localizacao_destino_id', valor: localizacaoId),
            ],
          ),
        if (movimentacao != null)
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              Text('Responsável de destino:', style: AppTypography.auxiliary(context)),
              Text(responsavel == null || responsavel.trim().isEmpty ? 'Não informado' : responsavel, style: estilo),
            ],
          ),
      ],
    );
  }
}

class _LinhaCampoAlterado extends ConsumerWidget {
  const _LinhaCampoAlterado({required this.campo});

  final SeiCampoAlterado campo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(campo.rotulo, style: AppTypography.auxiliary(context)),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LinhaValor(
                  rotulo: Text('Antes', style: AppTypography.auxiliary(context)),
                  valor: _ValorCampoEvento(chave: campo.chave, valor: campo.antes),
                ),
                const SizedBox(height: 2),
                _LinhaValor(
                  rotulo: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('→', style: AppTypography.body(context)),
                      const SizedBox(width: 4),
                      Text('Depois', style: AppTypography.auxiliary(context)),
                    ],
                  ),
                  valor: _ValorCampoEvento(chave: campo.chave, valor: campo.depois),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rótulo de largura fixa à esquerda + valor ocupando o resto da linha.
class _LinhaValor extends StatelessWidget {
  const _LinhaValor({required this.rotulo, required this.valor});

  final Widget rotulo;
  final Widget valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, child: rotulo),
        Expanded(child: valor),
      ],
    );
  }
}

/// Formata o valor bruto (jsonb) de um campo alterado — texto puro na
/// maioria dos casos; `decisao_localizacao`/`decisao_responsavel` viram um
/// rótulo pronto ([rotuloDecisaoBruta]); `destino_setor_id`/
/// `localizacao_destino_id` são UUIDs que PRECISAM ser resolvidos para nome
/// antes de aparecer (nunca mostrados brutos).
class _ValorCampoEvento extends ConsumerWidget {
  const _ValorCampoEvento({required this.chave, required this.valor});

  final String chave;
  final Object? valor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (chave) {
      case 'decisao_localizacao':
      case 'decisao_responsavel':
        return Text(rotuloDecisaoBruta(valor), style: AppTypography.body(context));

      case 'destino_setor_id':
        if (valor == null) return Text('—', style: AppTypography.body(context));
        final setoresAsync = ref.watch(setoresParaFiltroMovimentacoesProvider);
        return setoresAsync.when(
          data: (setores) {
            Setor? encontrado;
            for (final setor in setores) {
              if (setor.id == valor) {
                encontrado = setor;
                break;
              }
            }
            if (encontrado == null) return Text('Setor não encontrado', style: AppTypography.body(context));
            return Tooltip(
              message: encontrado.nomeComStatus,
              child: Text(encontrado.rotuloCompactoComStatus, style: AppTypography.body(context)),
            );
          },
          loading: () => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          error: (_, _) => Text('—', style: AppTypography.body(context)),
        );

      case 'localizacao_destino_id':
        if (valor == null) return Text('—', style: AppTypography.body(context));
        final nomeAsync = ref.watch(_localizacaoNomePorIdProvider(valor as String));
        return nomeAsync.when(
          data: (nome) => Text(nome ?? 'Localização não encontrada', style: AppTypography.body(context)),
          loading: () => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          error: (_, _) => Text('—', style: AppTypography.body(context)),
        );

      default:
        final texto = (valor as String?)?.trim();
        return Text(texto == null || texto.isEmpty ? '—' : texto, style: AppTypography.body(context));
    }
  }
}

final _localizacaoNomePorIdProvider = FutureProvider.autoDispose.family<String?, String>((ref, localizacaoId) async {
  final localizacao = await ref.watch(localizacaoRepositoryProvider).buscarPorId(localizacaoId);
  return localizacao?.nome;
});

(IconData, String) _visualDoTipo(SeiTipoEventoDocumento tipo) {
  switch (tipo) {
    case SeiTipoEventoDocumento.criacao:
      return (Icons.add_circle_outline, 'Documento criado');
    case SeiTipoEventoDocumento.edicao:
      return (Icons.edit_outlined, 'Edição de dados');
    case SeiTipoEventoDocumento.decisaoAlterada:
      return (Icons.tune, 'Decisão alterada');
    case SeiTipoEventoDocumento.itemConcluido:
      return (Icons.check_circle_outline, 'Item concluído');
    case SeiTipoEventoDocumento.itemCancelado:
      return (Icons.cancel_outlined, 'Item cancelado');
    case SeiTipoEventoDocumento.documentoCancelado:
      return (Icons.block, 'Itens pendentes cancelados');
    case SeiTipoEventoDocumento.tentativaBloqueada:
      return (Icons.lock_outline, 'Tentativa bloqueada');
  }
}

String _rotuloDescricao(SeiTipoEventoDocumento tipo) {
  switch (tipo) {
    case SeiTipoEventoDocumento.criacao:
      return 'Descrição';
    case SeiTipoEventoDocumento.edicao:
    case SeiTipoEventoDocumento.itemCancelado:
    case SeiTipoEventoDocumento.documentoCancelado:
      return 'Motivo';
    case SeiTipoEventoDocumento.decisaoAlterada:
    case SeiTipoEventoDocumento.itemConcluido:
    case SeiTipoEventoDocumento.tentativaBloqueada:
      return 'Descrição';
  }
}

/// Para um evento ITEM_CANCELADO, resolve o item afetado contra os itens JÁ
/// CARREGADOS de [documento] (nunca uma segunda consulta) — cancelamento
/// nunca remove a linha, só muda seu status. Cai para texto genérico só se o
/// item não estiver mais na lista carregada.
String _rotuloItemCancelado(SeiEventoDocumento evento, SeiDocumentoPendente documento) {
  final itemId = evento.itemId;
  if (itemId == null) return 'Item afetado: não identificado.';
  for (final item in documento.itens) {
    if (item.id == itemId) {
      final numero = item.numeroPatrimonio.valorEfetivo;
      return numero != null
          ? 'Item afetado: Patrimônio $numero (linha ${item.linha})'
          : 'Item afetado: linha ${item.linha}';
    }
  }
  return 'Item afetado: não encontrado na lista atual do documento.';
}

/// Item de um evento ITEM_CONCLUIDO: usa o número efetivo gravado no próprio
/// evento (`numero_patrimonio_efetivo`) e cai para a linha do documento.
String _rotuloItemConcluido(SeiEventoDocumento evento, SeiDocumentoPendente documento) {
  final numeroDoEvento = evento.dadosDepois?['numero_patrimonio_efetivo'] as String?;
  if (numeroDoEvento == null) return _rotuloItemCancelado(evento, documento);
  for (final item in documento.itens) {
    if (item.id == evento.itemId) return 'Item afetado: Patrimônio $numeroDoEvento (linha ${item.linha})';
  }
  return 'Item afetado: Patrimônio $numeroDoEvento';
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} às ${pad(local.hour)}:${pad(local.minute)}';
}
