import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/current_permissions_controller.dart';
import '../data/patrimonio_repository_supabase.dart';
import '../domain/patrimonio_scanner.dart';

/// Leitor de etiquetas patrimoniais pela câmera (Android — InvTec 4.0).
/// Pesquisa primeiro pelo tombamento ATUAL, depois pelo ANTERIOR (ver
/// [resolverCodigoEscaneado]); nunca cadastra/altera nada sozinho — só
/// decide o que mostrar. Inclui entrada manual como alternativa sempre
/// visível (câmera indisponível, etiqueta ilegível, ou só para testar sem
/// uma etiqueta física em mãos).
class PatrimonioScannerPage extends ConsumerStatefulWidget {
  const PatrimonioScannerPage({super.key});

  @override
  ConsumerState<PatrimonioScannerPage> createState() =>
      _PatrimonioScannerPageState();
}

class _PatrimonioScannerPageState extends ConsumerState<PatrimonioScannerPage>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController();
  final _manualController = TextEditingController();

  /// `true` entre o momento em que um código foi lido (câmera OU entrada
  /// manual) e a resposta do servidor chegar — nunca dispara uma segunda
  /// consulta enquanto uma já está em voo (regra do pedido: "impedir
  /// leituras repetidas de dispararem múltiplas consultas").
  bool _processando = false;

  /// Último código já resolvido com sucesso — enquanto a câmera continuar
  /// enquadrando a MESMA etiqueta (comum: a mão não se move tão rápido), o
  /// detector dispara `onDetect` várias vezes por segundo; sem esta
  /// trava, cada disparo reabriria a mesma consulta.
  String? _ultimoCodigoResolvido;

  /// `true` enquanto a câmera DEVERIA estar ligada (ocioso/pronta para
  /// escanear) — `false` durante o processamento e enquanto um
  /// resultado/erro está exibido aguardando "Escanear novamente"
  /// explícito. Só existe para [didChangeAppLifecycleState] saber se deve
  /// religar a câmera ao voltar do background: sem isso, voltar de um
  /// app em segundo plano reviveria a câmera por baixo de uma tela de
  /// resultado que o usuário ainda não dispensou.
  bool _cameraDeveEstarAtiva = true;

  ScannerResultado? _resultado;

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

  /// Encerra a câmera quando o app vai para segundo plano e a religa ao
  /// voltar — SEM isso, [MobileScanner] com um controller explícito (como
  /// aqui) nunca faz esse gerenciamento por conta própria (ele só o faz
  /// quando NENHUM controller é passado — ver a documentação de
  /// `MobileScanner.useAppLifecycleState`). Câmera ligada em segundo
  /// plano é desperdício de bateria e, em alguns aparelhos, o Android
  /// revoga o acesso sozinho — deixar como está causaria uma preview
  /// travada/quebrada ao voltar.
  ///
  /// MESMA lógica que o próprio `mobile_scanner` usa quando é ELE quem
  /// cuida do ciclo de vida (`_MobileScannerState.didChangeAppLifecycleState`):
  /// para (`stop`) só em [AppLifecycleState.inactive] — primeira transição
  /// ao perder foco, sempre antes de [AppLifecycleState.paused] — e
  /// religa (`start`) só em [AppLifecycleState.resumed] — última
  /// transição ao voltar, sempre depois de um novo `inactive`. `paused`/
  /// `hidden`/`detached` são sempre precedidos ou seguidos por
  /// `inactive`, então reagir duas vezes à mesma transição de fundo seria
  /// redundante.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_cameraDeveEstarAtiva) return;
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
    if (_processando) return;
    final barcode = capture.barcodes.isEmpty ? null : capture.barcodes.first;
    final codigo = barcode?.rawValue?.trim();
    if (codigo == null || codigo.isEmpty || codigo == _ultimoCodigoResolvido) {
      return;
    }
    unawaited(_processar(codigo));
  }

  Future<void> _processar(String codigoLido) async {
    setState(() {
      _processando = true;
      _cameraDeveEstarAtiva = false;
    });
    unawaited(_controller.stop());

    // resolverCodigoEscaneado nunca lança (toda falha já vem classificada
    // como ScannerResultadoTipo.acessoInsuficiente/falhaConsulta) — este
    // catch é só uma segunda camada de defesa contra um bug inesperado
    // aqui mesmo na página, nunca esperado disparar na prática.
    ScannerResultado resultado;
    try {
      final repositorio = ref.read(patrimonioRepositoryProvider);
      resultado = await resolverCodigoEscaneado(repositorio, codigoLido);
    } catch (_) {
      resultado = ScannerResultado.falhaConsulta(codigoLido);
    }
    if (!mounted) return;

    if (resultado.tipo == ScannerResultadoTipo.encontradoAtual ||
        resultado.tipo == ScannerResultadoTipo.encontradoAnterior) {
      setState(() => _processando = false);
      final id = resultado.encontrados.single.patrimonio.id;
      await context.push('/patrimonios/$id');
      if (!mounted) return;
      // Ao voltar do detalhe, a tela já está pronta para uma nova
      // leitura — nunca mostra o resultado anterior "preso" na tela.
      setState(() {
        _resultado = null;
        _ultimoCodigoResolvido = null;
        _cameraDeveEstarAtiva = true;
      });
      await _controller.start();
      return;
    }

    setState(() {
      _resultado = resultado;
      // Nunca trava a leitura repetida para resultados que não encontram
      // identidade nenhuma (ambíguo/não encontrado/inválido/falha) — só
      // para uma correspondência única já resolvida (ver [_onDetect]).
      _ultimoCodigoResolvido =
          resultado.tipo == ScannerResultadoTipo.ambiguo ? null : codigoLido;
      _processando = false;
    });
  }

  Future<void> _retomarLeitura() async {
    setState(() {
      _resultado = null;
      _ultimoCodigoResolvido = null;
      _cameraDeveEstarAtiva = true;
    });
    await _controller.start();
  }

  void _cadastrarComTombamento(String codigoLido) {
    context.push(
      '/patrimonios/novo?tombamento=${Uri.encodeQueryComponent(codigoLido)}',
    );
  }

  void _enviarCodigoManual() {
    final codigo = _manualController.text.trim();
    if (codigo.isEmpty) return;
    _manualController.clear();
    unawaited(_processar(codigo));
  }

  @override
  Widget build(BuildContext context) {
    final canCadastrar = ref.hasPermission('patrimonio.create');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear patrimônio'),
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
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) =>
                    _ErroCameraView(error: error),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _PainelResultado(
                processando: _processando,
                resultado: _resultado,
                canCadastrar: canCadastrar,
                manualController: _manualController,
                onBuscarManual: _enviarCodigoManual,
                onEscanearNovamente: _retomarLeitura,
                onCadastrar: _cadastrarComTombamento,
                onAbrirPatrimonio: (id) => context.push('/patrimonios/$id'),
              ),
            ),
          ),
        ],
      ),
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
        'Permissão de câmera negada. Ative a permissão de câmera do InvTec '
            'nas configurações do Android, ou use a entrada manual abaixo.',
      MobileScannerErrorCode.unsupported =>
        'Este dispositivo não tem uma câmera compatível. Use a entrada '
            'manual abaixo.',
      _ =>
        'Não foi possível abrir a câmera. Use a entrada manual abaixo.',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Painel fixo abaixo da câmera: estado da última leitura (se houver) +
/// entrada manual — SEMPRE visível, nunca só quando a câmera falha (regra
/// do pedido: "implementar... leitura manual alternativa").
class _PainelResultado extends StatelessWidget {
  const _PainelResultado({
    required this.processando,
    required this.resultado,
    required this.canCadastrar,
    required this.manualController,
    required this.onBuscarManual,
    required this.onEscanearNovamente,
    required this.onCadastrar,
    required this.onAbrirPatrimonio,
  });

  final bool processando;
  final ScannerResultado? resultado;
  final bool canCadastrar;
  final TextEditingController manualController;
  final VoidCallback onBuscarManual;
  final VoidCallback onEscanearNovamente;
  final void Function(String codigoLido) onCadastrar;
  final void Function(String patrimonioId) onAbrirPatrimonio;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (processando) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Center(child: CircularProgressIndicator()),
          ),
        ] else if (resultado != null) ...[
          _ResultadoView(
            resultado: resultado!,
            canCadastrar: canCadastrar,
            onCadastrar: onCadastrar,
            onAbrirPatrimonio: onAbrirPatrimonio,
            onEscanearNovamente: onEscanearNovamente,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: manualController,
                decoration: const InputDecoration(
                  labelText: 'Digitar número do patrimônio',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onBuscarManual(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(onPressed: onBuscarManual, child: const Text('Buscar')),
          ],
        ),
      ],
    );
  }
}

class _ResultadoView extends StatelessWidget {
  const _ResultadoView({
    required this.resultado,
    required this.canCadastrar,
    required this.onCadastrar,
    required this.onAbrirPatrimonio,
    required this.onEscanearNovamente,
  });

  final ScannerResultado resultado;
  final bool canCadastrar;
  final void Function(String codigoLido) onCadastrar;
  final void Function(String patrimonioId) onAbrirPatrimonio;
  final VoidCallback onEscanearNovamente;

  @override
  Widget build(BuildContext context) {
    switch (resultado.tipo) {
      case ScannerResultadoTipo.encontradoAtual:
      case ScannerResultadoTipo.encontradoAnterior:
        // Transitório: a navegação já ocorre sozinha ao resolver — nunca
        // deveria sobreviver até este build, mas nunca deixar em branco.
        return const SizedBox.shrink();

      case ScannerResultadoTipo.codigoInvalido:
        return _Aviso(
          icon: Icons.error_outline,
          mensagem: 'Código lido inválido (vazio ou só zeros).',
          onEscanearNovamente: onEscanearNovamente,
        );

      case ScannerResultadoTipo.acessoInsuficiente:
        // NUNCA oferece cadastro aqui — não se sabe se o patrimônio
        // existe, só que esta sessão não tem permissão para confirmar.
        return _Aviso(
          icon: Icons.lock_outline,
          mensagem:
              'Você não tem permissão para confirmar se este patrimônio '
              'existe. Fale com um administrador.',
          onEscanearNovamente: onEscanearNovamente,
        );

      case ScannerResultadoTipo.falhaConsulta:
        // NUNCA oferece cadastro aqui — a consulta não terminou, não é
        // uma resposta "não encontrado".
        return _Aviso(
          icon: Icons.error_outline,
          mensagem:
              'Não foi possível consultar o patrimônio agora. Verifique a '
              'conexão e tente novamente.',
          onEscanearNovamente: onEscanearNovamente,
        );

      case ScannerResultadoTipo.naoEncontrado:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Nenhum patrimônio encontrado para '
                  '"${resultado.codigoLido}" entre os que você pode acessar.',
                ),
                const SizedBox(height: AppSpacing.sm),
                if (canCadastrar)
                  FilledButton.icon(
                    onPressed: () => onCadastrar(resultado.codigoLido),
                    icon: const Icon(Icons.add),
                    label: const Text('Cadastrar patrimônio'),
                  )
                else
                  Text(
                    'Você não tem permissão para cadastrar novos patrimônios.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  onPressed: onEscanearNovamente,
                  child: const Text('Escanear novamente'),
                ),
              ],
            ),
          ),
        );

      case ScannerResultadoTipo.ambiguo:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mais de um patrimônio corresponde a '
                  '"${resultado.codigoLido}" — selecione qual abrir:',
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final item in resultado.encontrados)
                  ListTile(
                    dense: true,
                    title: Text('Nº ${item.patrimonio.numeroPatrimonio ?? '-'}'),
                    subtitle: Text(item.tipoNome),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onAbrirPatrimonio(item.patrimonio.id),
                  ),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  onPressed: onEscanearNovamente,
                  child: const Text('Escanear novamente'),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icon,
    required this.mensagem,
    required this.onEscanearNovamente,
  });

  final IconData icon;
  final String mensagem;
  final VoidCallback onEscanearNovamente;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(mensagem)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              onPressed: onEscanearNovamente,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
