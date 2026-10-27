import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../patrimonios/domain/patrimonio_detalhe.dart';

const _limiteResultados = 6;
const _debounceBusca = Duration(milliseconds: 300);

/// Busca rápida por PREFIXO de número patrimonial, aberta a partir de
/// "Consultar patrimônio" nas Ações rápidas do Dashboard — nunca uma
/// segunda listagem/página de Patrimônios: no máximo [_limiteResultados]
/// resultados, sempre resolvidos no servidor (ver
/// [PatrimonioRepository.buscarPorPrefixoNumeroPatrimonio]), zero consulta
/// antes do usuário digitar.
Future<void> showConsultarPatrimonioDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const ConsultarPatrimonioDialog(),
  );
}

class ConsultarPatrimonioDialog extends ConsumerStatefulWidget {
  const ConsultarPatrimonioDialog({super.key});

  @override
  ConsumerState<ConsultarPatrimonioDialog> createState() =>
      _ConsultarPatrimonioDialogState();
}

class _ConsultarPatrimonioDialogState
    extends ConsumerState<ConsultarPatrimonioDialog> {
  final _controller = TextEditingController();
  Timer? _debounceTimer;

  /// Incrementado a cada busca disparada — uma resposta de uma busca já
  /// substituída por uma mais nova (termo digitado mudou antes dela voltar)
  /// nunca sobrescreve o estado atual.
  int _requestId = 0;

  bool _carregando = false;
  List<PatrimonioDetalhe>? _resultados;
  Object? _erro;

  /// Termo que efetivamente produziu [_resultados] — Enter só seleciona
  /// automaticamente quando este termo bate com o texto atual (nunca com
  /// uma busca anterior ainda "presa" na tela enquanto o debounce da
  /// digitação mais recente não resolveu).
  String? _ultimoTermoBuscado;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _aoDigitar(String texto) {
    _debounceTimer?.cancel();
    final termo = texto.trim();
    if (termo.isEmpty) {
      setState(() {
        _carregando = false;
        _resultados = null;
        _erro = null;
      });
      return;
    }
    _debounceTimer = Timer(_debounceBusca, () => _buscar(termo));
  }

  Future<void> _buscar(String termo) async {
    final id = ++_requestId;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resultados = await ref
          .read(patrimonioRepositoryProvider)
          .buscarPorPrefixoNumeroPatrimonio(termo, limit: _limiteResultados);
      if (!mounted || id != _requestId) return;
      setState(() {
        _carregando = false;
        _resultados = resultados;
        _ultimoTermoBuscado = termo;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _carregando = false;
        _erro = e;
      });
    }
  }

  void _tentarNovamente() {
    final termo = _controller.text.trim();
    if (termo.isEmpty) return;
    _buscar(termo);
  }

  void _selecionar(PatrimonioDetalhe item) {
    Navigator.of(context).pop();
    context.go('/patrimonios/${item.patrimonio.id}');
  }

  /// Enter nunca seleciona "o primeiro resultado" de uma lista ambígua —
  /// só age quando há EXATAMENTE uma correspondência já resolvida para o
  /// termo atual (ver [_ultimoTermoBuscado]).
  void _aoSubmeter(String texto) {
    final resultados = _resultados;
    if (resultados == null || resultados.length != 1) return;
    if (_ultimoTermoBuscado != texto.trim()) return;
    _selecionar(resultados.single);
  }

  @override
  Widget build(BuildContext context) {
    // Teclado aberto (Android) reduz a altura que o `Dialog` recebe do
    // framework (ver `AnimatedPadding` interno de `Dialog`, que soma
    // `MediaQuery.viewInsets` ao redor da caixa) — antes, uma região de
    // conteúdo com altura FIXA (`SizedBox(height: 260)`) exigia mais
    // espaço do que o disponível nesse cenário, causando
    // "BOTTOM OVERFLOWED". Agora a região de conteúdo é `Flexible`
    // (nunca mais fixa): ocupa o que sobrar depois do título, campo de
    // busca e botão "Fechar" (que continuam sempre visíveis), e rola
    // internamente (`SingleChildScrollView`) em vez de estourar quando
    // isso não for suficiente — nenhum tamanho incompatível com a
    // abertura do teclado permanece na árvore.
    final tecladoAberto = MediaQuery.of(context).viewInsets.bottom > 0;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Consultar patrimônio',
                style: AppTypography.pageSubtitle(context),
              ),
              const SizedBox(height: AppSpacing.md),
              // Campo de busca nunca entra na área flexível/rolável —
              // continua sempre visível e acessível, com ou sem teclado.
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _aoDigitar,
                onSubmitted: _aoSubmeter,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Digite o número patrimonial',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: _conteudo(context, compacto: tecladoAberto),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Fora da área flexível/rolável — "Fechar" continua
              // alcançável mesmo com o teclado aberto e o conteúdo
              // reduzido ao mínimo.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [compacto] (teclado aberto): troca a ilustração de estado vazio
  /// (ícone grande + mensagem) por uma linha de texto discreta — "oculte
  /// o estado vazio ilustrativo enquanto o teclado estiver aberto,
  /// recuperando-o quando houver espaço" — nunca aplicado aos resultados
  /// de verdade nem ao estado de erro (cuja ação "Tentar novamente"
  /// precisa continuar visível e completa).
  Widget _conteudo(BuildContext context, {required bool compacto}) {
    Widget estadoIlustrativo({required IconData icon, required String message}) {
      if (compacto) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(message, style: AppTypography.auxiliary(context)),
        );
      }
      return Center(child: EmptyState(icon: icon, message: message));
    }

    if (_controller.text.trim().isEmpty) {
      return estadoIlustrativo(
        icon: Icons.search,
        message: 'Digite um número patrimonial para pesquisar.',
      );
    }
    if (_carregando) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_erro != null) {
      return Center(
        child: EmptyState(
          icon: Icons.error_outline,
          message: 'Não foi possível pesquisar os patrimônios.',
          actionLabel: 'Tentar novamente',
          onAction: _tentarNovamente,
        ),
      );
    }

    final resultados = _resultados ?? const [];
    if (resultados.isEmpty) {
      return estadoIlustrativo(
        icon: Icons.search_off,
        message: 'Nenhum patrimônio encontrado.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in resultados)
          _ResultadoRow(item: item, onTap: () => _selecionar(item)),
        // Heurística sem custo extra de rede (nunca um COUNT(*) só para
        // isto): atingiu exatamente o LIMIT -> pode haver mais.
        if (resultados.length == _limiteResultados) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Continue digitando para refinar a pesquisa.',
            style: AppTypography.auxiliary(context),
          ),
        ],
      ],
    );
  }
}

class _ResultadoRow extends StatelessWidget {
  const _ResultadoRow({required this.item, required this.onTap});

  final PatrimonioDetalhe item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detalhes = [
      item.tipoNome,
      item.setorExibidoCompacto,
      if (item.localizacaoNome != null) item.localizacaoNome!,
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.patrimonio.numeroPatrimonio ?? 'Sem número patrimonial',
              style: AppTypography.body(
                context,
              )?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              detalhes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.auxiliary(context),
            ),
          ],
        ),
      ),
    );
  }
}
