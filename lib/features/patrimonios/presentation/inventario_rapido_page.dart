import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../localizacoes/domain/localizacao.dart';
import '../../localizacoes/presentation/localizacoes_providers.dart';
import '../domain/inventario_rapido.dart';
import '../domain/inventario_rapido_relatorio.dart';
import '../domain/patrimonio_detalhe.dart';
import '../domain/patrimonio_scanner.dart';
import 'inventario_rapido_controller.dart';
import 'widgets/confirm_discard_dialog.dart';

/// Inventário Rápido (Android — InvTec 4.0, protótipo local): conferência
/// de MÚLTIPLOS patrimônios de uma localização, um após o outro. Reutiliza
/// a MESMA resolução exata do leitor de patrimônio avulso
/// ([resolverCodigoEscaneado]) — nunca uma segunda lógica de busca.
///
/// NUNCA grava nada no Supabase: a sessão inteira vive só em memória
/// ([InventarioRapidoController]), inclusive a comparação de localização
/// (só exibida, nunca aplicada). O único artefato que esta tela produz é
/// um arquivo CSV local, gerado sob demanda.
class InventarioRapidoPage extends ConsumerStatefulWidget {
  const InventarioRapidoPage({super.key});

  @override
  ConsumerState<InventarioRapidoPage> createState() => _InventarioRapidoPageState();
}

class _InventarioRapidoPageState extends ConsumerState<InventarioRapidoPage>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController();
  final _manualController = TextEditingController();
  String? _ultimoCodigoResolvido;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Mesma lógica de ciclo de vida do leitor avulso (`PatrimonioScannerPage`)
  /// — ver o comentário lá para o porquê de só reagir a `inactive`/`resumed`.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
      case AppLifecycleState.inactive:
        unawaited(_controller.stop());
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final estado = ref.read(inventarioRapidoControllerProvider);
    if (estado == null || estado.processando) return;
    final barcode = capture.barcodes.isEmpty ? null : capture.barcodes.first;
    final codigo = barcode?.rawValue?.trim();
    if (codigo == null || codigo.isEmpty || codigo == _ultimoCodigoResolvido) {
      return;
    }
    _ultimoCodigoResolvido = codigo;
    unawaited(
      ref.read(inventarioRapidoControllerProvider.notifier).processarCodigo(codigo),
    );
  }

  void _enviarCodigoManual() {
    final codigo = _manualController.text.trim();
    if (codigo.isEmpty) return;
    _manualController.clear();
    _ultimoCodigoResolvido = codigo;
    unawaited(
      ref.read(inventarioRapidoControllerProvider.notifier).processarCodigo(codigo),
    );
  }

  void _iniciarSessao(Localizacao localizacao) {
    ref.read(inventarioRapidoControllerProvider.notifier).iniciarSessao(
      localizacaoId: localizacao.id,
      localizacaoNome: localizacao.nome,
    );
  }

  Future<bool> _confirmarEncerrarComLeituras(int totalLeituras) {
    if (totalLeituras == 0) return Future.value(true);
    return confirmarDescartarAlteracoes(
      context,
      title: 'Encerrar sessão de inventário?',
      message:
          '$totalLeituras leitura(s) desta sessão ainda não foram exportadas '
          'e serão perdidas.',
    );
  }

  Future<void> _sair(InventarioRapidoEstado estado) async {
    final confirmar = await _confirmarEncerrarComLeituras(estado.totalLeituras);
    if (!confirmar || !mounted) return;
    ref.read(inventarioRapidoControllerProvider.notifier).encerrarSessao();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/patrimonios');
    }
  }

  Future<void> _finalizarSessao(InventarioRapidoEstado estado) async {
    if (estado.leituras.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Nenhuma leitura para exportar ainda.')),
        );
      return;
    }

    final csv = gerarCsvInventario(
      localizacaoSelecionadaNome: estado.localizacaoNome,
      localizacaoSelecionadaId: estado.localizacaoId,
      leituras: estado.leituras,
    );
    final nomeArquivo =
        'inventario_${_nomeArquivoSeguro(estado.localizacaoNome)}_'
        '${DateTime.now().millisecondsSinceEpoch}.csv';

    Uri? salvo;
    try {
      salvo = await FilePicker.saveFile(
        fileName: nomeArquivo,
        bytes: Uint8List.fromList(_utf8ComBom(csv)),
        mimeType: 'text/csv',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar o relatório.')),
        );
      return;
    }
    if (!mounted || salvo == null) return; // usuário cancelou o diálogo

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Relatório salvo: $nomeArquivo')));

    final encerrar = await confirmarDescartarAlteracoes(
      context,
      title: 'Encerrar esta sessão de conferência?',
      message:
          'O relatório já foi salvo. Encerrar limpa a sessão para começar '
          'uma nova conferência.',
    );
    if (encerrar && mounted) {
      ref.read(inventarioRapidoControllerProvider.notifier).encerrarSessao();
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(inventarioRapidoControllerProvider);

    if (estado == null) {
      return _SelecionarLocalizacaoView(onSelecionar: _iniciarSessao);
    }

    return PopScope(
      canPop: estado.leituras.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _sair(estado);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Inventário — ${estado.localizacaoNome}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _sair(estado),
          ),
          actions: [
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                if (state.torchState == TorchState.unavailable) {
                  return const SizedBox.shrink();
                }
                final ligada = state.torchState == TorchState.on;
                return IconButton(
                  onPressed: _controller.toggleTorch,
                  tooltip: ligada ? 'Desligar lanterna' : 'Ligar lanterna',
                  icon: Icon(ligada ? Icons.flash_on : Icons.flash_off),
                );
              },
            ),
            IconButton(
              onPressed: () => _finalizarSessao(estado),
              tooltip: 'Gerar relatório (CSV)',
              icon: const Icon(Icons.save_alt_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            _ContadoresBar(estado: estado),
            SizedBox(
              height: 220,
              child: ColoredBox(
                color: Colors.black,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _ErroCameraView(error: error),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      decoration: const InputDecoration(
                        labelText: 'Digitar número do patrimônio',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _enviarCodigoManual(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _enviarCodigoManual,
                    child: const Text('Buscar'),
                  ),
                ],
              ),
            ),
            if (estado.processando) const LinearProgressIndicator(),
            Expanded(
              child: estado.leituras.isEmpty
                  ? const EmptyState(
                      icon: Icons.qr_code_scanner_outlined,
                      message: 'Nenhuma leitura ainda — escaneie o primeiro patrimônio.',
                    )
                  : _ListaLeituras(
                      estado: estado,
                      onRemover: (id) => ref
                          .read(inventarioRapidoControllerProvider.notifier)
                          .removerLeitura(id),
                      onTentarNovamente: (id) => ref
                          .read(inventarioRapidoControllerProvider.notifier)
                          .tentarNovamente(id),
                      onAbrirPatrimonio: (id) => context.push('/patrimonios/$id'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Remove acentos/espaços problemáticos do nome da localização para um
/// nome de arquivo seguro em qualquer sistema de arquivos — nunca usado
/// para exibição, só para o CSV exportado.
String _nomeArquivoSeguro(String nome) =>
    nome.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toLowerCase();

/// BOM (Byte Order Mark) UTF-8 — sem isso, o Excel (comum no GETEC) abre
/// acentuação de forma incorreta em arquivos CSV UTF-8 puros.
List<int> _utf8ComBom(String texto) => [0xEF, 0xBB, 0xBF, ...utf8.encode(texto)];

class _SelecionarLocalizacaoView extends ConsumerStatefulWidget {
  const _SelecionarLocalizacaoView({required this.onSelecionar});

  final void Function(Localizacao localizacao) onSelecionar;

  @override
  ConsumerState<_SelecionarLocalizacaoView> createState() =>
      _SelecionarLocalizacaoViewState();
}

class _SelecionarLocalizacaoViewState extends ConsumerState<_SelecionarLocalizacaoView> {
  Localizacao? _selecionada;

  @override
  Widget build(BuildContext context) {
    final localizacoesAsync = ref.watch(localizacoesParaFiltroProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Inventário rápido')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InvTecPageHeader(
              title: 'Nova conferência',
              subtitle:
                  'Selecione a localização que será conferida. Nenhum dado é '
                  'alterado no cadastro — esta é só uma sessão temporária de '
                  'leitura.',
            ),
            const SizedBox(height: AppSpacing.lg),
            localizacoesAsync.when(
              data: (localizacoes) {
                if (localizacoes.isEmpty) {
                  return const EmptyState(
                    icon: Icons.location_off_outlined,
                    message: 'Nenhuma localização ativa cadastrada.',
                  );
                }
                return DropdownButtonFormField<Localizacao>(
                  initialValue: _selecionada,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Localização a conferir',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final localizacao in localizacoes)
                      DropdownMenuItem(
                        value: localizacao,
                        child: Text(localizacao.nome, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (valor) => setState(() => _selecionada = valor),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const EmptyState(
                icon: Icons.error_outline,
                message: 'Não foi possível carregar as localizações.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _selecionada == null
                  ? null
                  : () => widget.onSelecionar(_selecionada!),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar conferência'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContadoresBar extends StatelessWidget {
  const _ContadoresBar({required this.estado});

  final InventarioRapidoEstado estado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Contador(label: 'Leituras', valor: estado.totalLeituras),
          _Contador(label: 'Encontrados', valor: estado.totalEncontrados),
          _Contador(label: 'Pendências', valor: estado.totalPendencias),
        ],
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({required this.label, required this.valor});

  final String label;
  final int valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$valor', style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ErroCameraView extends StatelessWidget {
  const _ErroCameraView({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final mensagem = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Permissão de câmera negada. Use a entrada manual abaixo.',
      MobileScannerErrorCode.unsupported =>
        'Câmera não disponível. Use a entrada manual abaixo.',
      _ => 'Não foi possível abrir a câmera. Use a entrada manual abaixo.',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            mensagem,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _ListaLeituras extends StatelessWidget {
  const _ListaLeituras({
    required this.estado,
    required this.onRemover,
    required this.onTentarNovamente,
    required this.onAbrirPatrimonio,
  });

  final InventarioRapidoEstado estado;
  final void Function(String id) onRemover;
  final void Function(String id) onTentarNovamente;
  final void Function(String patrimonioId) onAbrirPatrimonio;

  @override
  Widget build(BuildContext context) {
    // Mais recente primeiro — a leitura que o usuário acabou de fazer é
    // a que mais importa revisar.
    final leituras = estado.leituras.reversed.toList();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: leituras.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final leitura = leituras[index];
        return _LeituraTile(
          leitura: leitura,
          localizacaoSelecionadaId: estado.localizacaoId,
          onRemover: () => onRemover(leitura.id),
          onTentarNovamente: leitura.ePendencia
              ? () => onTentarNovamente(leitura.id)
              : null,
          onAbrir: leitura.patrimonioUnico == null
              ? null
              : () => onAbrirPatrimonio(leitura.patrimonioUnico!.patrimonio.id),
        );
      },
    );
  }
}

class _LeituraTile extends StatelessWidget {
  const _LeituraTile({
    required this.leitura,
    required this.localizacaoSelecionadaId,
    required this.onRemover,
    required this.onTentarNovamente,
    required this.onAbrir,
  });

  final InventarioLeitura leitura;
  final String localizacaoSelecionadaId;
  final VoidCallback onRemover;
  final VoidCallback? onTentarNovamente;
  final VoidCallback? onAbrir;

  @override
  Widget build(BuildContext context) {
    final patrimonio = leitura.patrimonioUnico;
    final diverge = patrimonio != null &&
        leituraDivergeDaLocalizacao(leitura, localizacaoSelecionadaId);

    return ListTile(
      leading: Icon(_iconeDe(leitura.status), color: _corDe(context, leitura.status)),
      title: Text(
        patrimonio != null
            ? 'Nº ${patrimonio.patrimonio.numeroPatrimonio ?? '-'}'
            : leitura.codigoLido,
      ),
      subtitle: Text(_subtitulo(patrimonio, diverge)),
      onTap: onAbrir,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onTentarNovamente != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Tentar novamente',
              onPressed: onTentarNovamente,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remover leitura',
            onPressed: onRemover,
          ),
        ],
      ),
    );
  }

  String _subtitulo(PatrimonioDetalhe? patrimonio, bool diverge) {
    if (patrimonio == null) return rotuloStatusInventario(leitura.status);
    final localizacaoCadastrada = patrimonio.localizacaoNome ?? 'Sem localização';
    return diverge
        ? 'Cadastrado em "$localizacaoCadastrada" (diferente desta conferência)'
        : 'Localização confirmada: $localizacaoCadastrada';
  }

  IconData _iconeDe(ScannerResultadoTipo status) => switch (status) {
    ScannerResultadoTipo.encontradoAtual => Icons.check_circle_outline,
    ScannerResultadoTipo.encontradoAnterior => Icons.history,
    ScannerResultadoTipo.ambiguo => Icons.help_outline,
    ScannerResultadoTipo.naoEncontrado => Icons.search_off,
    ScannerResultadoTipo.codigoInvalido => Icons.error_outline,
    ScannerResultadoTipo.acessoInsuficiente => Icons.lock_outline,
    ScannerResultadoTipo.falhaConsulta => Icons.wifi_off,
  };

  Color _corDe(BuildContext context, ScannerResultadoTipo status) {
    final scheme = Theme.of(context).colorScheme;
    return status.ePendenciaDeInventario ? scheme.error : scheme.primary;
  }
}
