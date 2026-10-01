import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/pagination_controls.dart';
import '../sei_pendencias_controller.dart';
import '../sei_pendencias_filtro.dart';
import 'sei_pendencia_detalhe_dialog.dart';
import 'sei_pendencias_list.dart';

/// Aba "Pendências / Documentos SEI" (PROMPT 11.3, seção 4) — SEPARADA do
/// histórico de movimentações efetivas: documentos pendentes nunca entram
/// em `movimentacoes`, então esta lista vem inteiramente de
/// `DocumentosSeiRepository`, nunca de `MovimentacaoRepository`.
class SeiPendenciasSection extends ConsumerStatefulWidget {
  const SeiPendenciasSection({super.key});

  @override
  ConsumerState<SeiPendenciasSection> createState() => _SeiPendenciasSectionState();
}

class _SeiPendenciasSectionState extends ConsumerState<SeiPendenciasSection> {
  final _buscaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _abrirDetalhe(String documentoId) async {
    await showSeiPendenciaDetalheDialog(context, documentoId);
    if (!mounted) return;
    await ref.read(seiPendenciasControllerProvider.notifier).recarregar();
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(seiPendenciasControllerProvider);
    final termoBusca = _buscaController.text.trim();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _buscaController,
                onChanged: (valor) => ref.read(seiPendenciasControllerProvider.notifier).buscarPorDocumento(valor),
                decoration: InputDecoration(
                  hintText: 'Buscar por número do documento SEI...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscaController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _buscaController.clear();
                            ref.read(seiPendenciasControllerProvider.notifier).buscarPorDocumento('');
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          stateAsync.when(
            data: (state) {
              final itens = state.resultado.itens;
              if (itens.isEmpty) {
                return Card(
                  child: EmptyState(
                    icon: Icons.description_outlined,
                    message: state.filtro.temFiltroAtivo || termoBusca.isNotEmpty
                        ? 'Nenhum documento SEI pendente encontrado para este filtro.'
                        : 'Nenhum documento SEI pendente ainda — importe um despacho e salve como pendência.',
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeiPendenciasList(itens: itens, onAbrir: (documento) => _abrirDetalhe(documento.id)),
                  const SizedBox(height: AppSpacing.lg),
                  PaginationControls(
                    paginaAtual: state.filtro.pagina,
                    totalPaginas: state.totalPaginas,
                    totalItens: state.resultado.total,
                    tamanhoPagina: state.filtro.tamanhoPagina,
                    tamanhosPaginaPermitidos: seiPendenciasTamanhosPaginaPermitidos,
                    onChanged: (pagina) => ref.read(seiPendenciasControllerProvider.notifier).irParaPagina(pagina),
                    onTamanhoPaginaChanged: (tamanho) =>
                        ref.read(seiPendenciasControllerProvider.notifier).definirTamanhoPagina(tamanho),
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Center(
              child: EmptyState(
                icon: Icons.error_outline,
                message: 'Não foi possível acessar as pendências. Tente novamente.',
                actionLabel: 'Tentar novamente',
                onAction: () => ref.read(seiPendenciasControllerProvider.notifier).recarregar(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
