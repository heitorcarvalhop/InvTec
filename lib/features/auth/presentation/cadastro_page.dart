import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/signup_validators.dart';
import 'sign_up_controller.dart';

/// Formata a digitação do CPF como `000.000.000-00` — só máscara visual: o
/// texto enviado ao controller continua sendo o que o usuário vê aqui (com
/// pontuação), e `validarCpf`/o repositório já normalizam para 11 dígitos
/// internamente (ver `signup_validators.dart`). O cursor é sempre mantido no
/// fim do texto — simplificação deliberada (nunca editar CPF no meio é um
/// caso raro o suficiente para não justificar a complexidade de preservar a
/// posição do cursor).
class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitados = digitos.length > 11 ? digitos.substring(0, 11) : digitos;

    final buffer = StringBuffer();
    for (var i = 0; i < limitados.length; i++) {
      buffer.write(limitados[i]);
      if (i == 2 || i == 5) buffer.write('.');
      if (i == 8) buffer.write('-');
    }

    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Formulário de autocadastro (`/cadastro`) — único jeito de criar uma conta
/// no InvTec sem ser via um ADMIN. Toda conta criada aqui nasce em `PENDING`
/// (ver `handle_new_user` no banco) e só opera o sistema depois de aprovada.
class CadastroPage extends ConsumerStatefulWidget {
  const CadastroPage({super.key});

  @override
  ConsumerState<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends ConsumerState<CadastroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmacaoController = TextEditingController();

  bool _obscureSenha = true;
  bool _obscureConfirmacao = true;
  bool _isSubmitting = false;
  bool _confirmacaoEmailPendente = false;
  String _senhaAtual = '';

  @override
  void dispose() {
    _nomeController.dispose();
    _cpfController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmacaoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      final outcome = await ref
          .read(signUpControllerProvider)
          .signUp(
            nome: _nomeController.text,
            cpf: _cpfController.text,
            email: _emailController.text,
            senha: _senhaController.text,
          );
      if (!mounted) return;

      switch (outcome) {
        case SignUpSuccess():
          // authControllerProvider/router já movem o usuário para
          // /acesso/pendente automaticamente quando a sessão for criada —
          // o SnackBar é só uma confirmação rápida, não bloqueia nada.
          _showMessage('Cadastro realizado com sucesso.');
        case SignUpEmailConfirmationRequired():
          setState(() => _confirmacaoEmailPendente = true);
        case SignUpFailure(mensagem: final mensagem):
          _showMessage(mensagem);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Mobile (Fase 2 — densidade): mesmo formulário, menos respiro ao
    // redor — nenhum campo/botão muda de tamanho (mesmo padrão do Login).
    final mobile = context.screenSize == ScreenSize.mobile;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: mobile ? AppSpacing.lg : AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.seed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      Icons.person_add_alt_outlined,
                      color: AppColors.seed,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Criar conta',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Sistema de Controle Patrimonial',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: mobile ? AppSpacing.lg : AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(
                        mobile ? AppSpacing.md : AppSpacing.lg,
                      ),
                      child: _confirmacaoEmailPendente
                          ? _ConfirmacaoEmailPanel(
                              onVoltarParaLogin: () => context.go('/login'),
                            )
                          : _buildForm(theme),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final satisfeitos = avaliarRequisitosSenha(_senhaAtual).toSet();

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nomeController,
            enabled: !_isSubmitting,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Nome completo',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: validarNome,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _cpfController,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [_CpfInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'CPF',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: validarCpf,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _emailController,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: validarEmail,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _senhaController,
            enabled: !_isSubmitting,
            obscureText: _obscureSenha,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Senha',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscureSenha ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(
                  _obscureSenha
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscureSenha = !_obscureSenha),
              ),
            ),
            onChanged: (value) => setState(() => _senhaAtual = value),
            validator: validarSenha,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RequisitosSenhaChecklist(satisfeitos: satisfeitos),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _confirmacaoController,
            enabled: !_isSubmitting,
            obscureText: _obscureConfirmacao,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Confirmar senha',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscureConfirmacao
                    ? 'Mostrar senha'
                    : 'Ocultar senha',
                icon: Icon(
                  _obscureConfirmacao
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirmacao = !_obscureConfirmacao),
              ),
            ),
            validator: (value) =>
                validarConfirmacaoSenha(_senhaController.text, value),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Criar conta'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _isSubmitting ? null : () => context.go('/login'),
            child: const Text('Já tem conta? Entrar'),
          ),
        ],
      ),
    );
  }
}

/// Checklist visual ✓/○ dos 5 requisitos de senha — atualiza a cada tecla
/// digitada, sem complexímetro: só indica quais já estão satisfeitos.
class _RequisitosSenhaChecklist extends StatelessWidget {
  const _RequisitosSenhaChecklist({required this.satisfeitos});

  final Set<RequisitoSenha> satisfeitos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final requisito in RequisitoSenha.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  satisfeitos.contains(requisito)
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 16,
                  color: satisfeitos.contains(requisito)
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    requisito.descricao,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: satisfeitos.contains(requisito)
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Painel exibido no lugar do formulário quando o Supabase exige confirmação
/// de e-mail antes de liberar a sessão (sem login automático, então não há
/// navegação automática a esperar) — ver `SignUpEmailConfirmationRequired`.
class _ConfirmacaoEmailPanel extends StatelessWidget {
  const _ConfirmacaoEmailPanel({required this.onVoltarParaLogin});

  final VoidCallback onVoltarParaLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          color: theme.colorScheme.primary,
          size: 40,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Cadastro criado. Verifique seu e-mail para confirmar a conta e depois faça login.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: onVoltarParaLogin,
          child: const Text('Voltar para o login'),
        ),
      ],
    );
  }
}
