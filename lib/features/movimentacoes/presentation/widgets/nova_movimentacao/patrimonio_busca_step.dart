import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../../patrimonios/domain/patrimonio_search_field.dart';
import '../../../../patrimonios/presentation/widgets/patrimonio_status_chip.dart';

/// Passo 1 do wizard de Nova Movimentação (PROMPT 10.2, seção 4): localizar
/// o patrimônio por número/série/descrição, reaproveitando a MESMA busca
/// server-side já usada na listagem de Patrimônios
/// ([PatrimonioRepository.listar] com `campoBusca: tudo`) — nunca carrega
/// os 1.744 patrimônios em memória para montar um seletor.
class PatrimonioBuscaStep extends ConsumerStatefulWidget {
  const PatrimonioBuscaStep({
    super.key,
    required this.selecionado,
    required this.onSelecionar,
    required this.onTrocar,
  });

  final PatrimonioDetalhe? selecionado;
  final ValueChanged<PatrimonioDetalhe> onSelecionar;

  /// Limpa a seleção atual (volta para a busca) — estado vive no wizard
  /// pai, não aqui: trocar de patrimônio também precisa limpar tipo/destino/
  /// responsável já escolhidos, que este widget não conhece.
  final VoidCallback onTrocar;

  @override
  ConsumerState<PatrimonioBuscaStep> createState() => _PatrimonioBuscaStepState();
}

class _PatrimonioBuscaStepState extends ConsumerState<PatrimonioBuscaStep> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PatrimonioDetalhe>? _resultados;
  bool _buscando = false;
  Object? _erro;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _buscar(String texto) {
    _debounce?.cancel();
    final termo = texto.trim();
    if (termo.isEmpty) {
      setState(() {
        _resultados = null;
        _erro = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _buscando = true;
        _erro = null;
      });
      try {
        final resultado = await ref
            .read(patrimonioRepositoryProvider)
            .listar(busca: termo, campoBusca: PatrimonioSearchField.tudo, limit: 10);
        if (!mounted) return;
        setState(() {
          _resultados = resultado.itens;
          _buscando = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _erro = e;
          _buscando = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selecionado != null) {
      return _ResumoPatrimonio(detalhe: widget.selecionado!, onTrocar: widget.onTrocar);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecione o patrimônio',
          style: AppTypography.pageSubtitle(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Busque por número de patrimônio, número de série ou descrição.',
          style: AppTypography.auxiliary(context),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _buscar,
          decoration: const InputDecoration(
            hintText: 'Número, série ou descrição...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_buscando) const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: CircularProgressIndicator())),
        if (_erro != null)
          Text(
            'Não foi possível buscar patrimônios. Tente novamente.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!_buscando && _erro == null && _resultados != null)
          _resultados!.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('Nenhum patrimônio encontrado para esta busca.'),
                )
              : _ListaResultados(itens: _resultados!, onSelecionar: widget.onSelecionar),
      ],
    );
  }
}

class _ListaResultados extends StatelessWidget {
  const _ListaResultados({required this.itens, required this.onSelecionar});

  final List<PatrimonioDetalhe> itens;
  final ValueChanged<PatrimonioDetalhe> onSelecionar;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < itens.length; i++) ...[
            ListTile(
              title: Text(itens[i].patrimonio.numeroPatrimonio ?? '(sem número)'),
              subtitle: Text('${itens[i].tipoNome} · ${itens[i].setorNome}'),
              trailing: PatrimonioStatusChip(status: itens[i].patrimonio.status),
              onTap: () => onSelecionar(itens[i]),
            ),
            if (i < itens.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

/// Resumo do patrimônio escolhido (seção 4 do prompt): patrimônio,
/// equipamento, status atual, setor atual, localização atual, responsável
/// atual — nunca mostra um UUID cru.
class _ResumoPatrimonio extends StatelessWidget {
  const _ResumoPatrimonio({required this.detalhe, required this.onTrocar});

  final PatrimonioDetalhe detalhe;
  final VoidCallback onTrocar;

  @override
  Widget build(BuildContext context) {
    final p = detalhe.patrimonio;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.numeroPatrimonio ?? '(sem número)',
                    style: AppTypography.pageSubtitle(context),
                  ),
                ),
                PatrimonioStatusChip(status: p.status),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _LinhaResumo('Equipamento', detalhe.tipoNome),
            _LinhaResumo('Setor atual', detalhe.setorNome),
            _LinhaResumo('Localização atual', detalhe.localizacaoNome ?? '—'),
            _LinhaResumo('Responsável atual', p.responsavelAtual ?? '—'),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onTrocar,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Trocar patrimônio'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(rotulo, style: AppTypography.auxiliary(context))),
          Expanded(child: Text(valor, style: AppTypography.body(context))),
        ],
      ),
    );
  }
}
