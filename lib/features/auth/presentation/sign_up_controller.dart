import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error_messages.dart';
import '../../../core/errors/app_exception.dart';
import '../data/auth_repository_supabase.dart';
import '../domain/signup_validators.dart';

/// Desfecho de [SignUpController.signUp] — a `CadastroPage` (design-ui)
/// decide o que mostrar a partir deste enum, nunca inspecionando exceções.
sealed class SignUpOutcome {
  const SignUpOutcome();
}

/// Sessão criada (login automático) — o usuário cai em PENDING
/// automaticamente via `authStateChanges`/`authControllerProvider`, sem
/// precisar fazer login manualmente depois do cadastro.
class SignUpSuccess extends SignUpOutcome {
  const SignUpSuccess();
}

/// Sem sessão — o Supabase exige confirmação de e-mail antes de liberar o
/// acesso. A UI deve mostrar algo como "Cadastro criado. Verifique seu
/// e-mail para confirmar a conta e depois faça login.".
class SignUpEmailConfirmationRequired extends SignUpOutcome {
  const SignUpEmailConfirmationRequired();
}

/// Falha de validação OU do servidor — [mensagem] já está traduzida e
/// pronta para exibição direta (nunca expõe detalhe técnico).
class SignUpFailure extends SignUpOutcome {
  const SignUpFailure(this.mensagem);
  final String mensagem;
}

final signUpControllerProvider = Provider<SignUpController>((ref) {
  return SignUpController(ref);
});

/// Controller do fluxo de cadastro (`/cadastro`, página ainda não criada —
/// ver `lib/features/auth/presentation/cadastro_page.dart`, placeholder
/// temporário).
///
/// Divisão de validação (documentada para quem for escrever a
/// `CadastroPage`): os `FormField.validator` da página devem usar
/// diretamente as funções PURAS de `signup_validators.dart`
/// (`validarNome`/`validarCpf`/`validarEmail`/`validarSenha`/
/// `validarConfirmacaoSenha`) — nenhuma duplicação de regex na UI. Este
/// controller REVALIDA as mesmas regras (defesa em profundidade — nunca
/// confia que a UI sempre validou antes de chamar `signUp`) e é o único
/// lugar que traduz erros vindos do SERVIDOR (rede, CPF/e-mail duplicado,
/// erro genérico do GoTrue) via [traduzirErroSupabase].
class SignUpController {
  SignUpController(this._ref);

  final Ref _ref;

  Future<SignUpOutcome> signUp({
    required String nome,
    required String cpf,
    required String email,
    required String senha,
  }) async {
    final erroNome = validarNome(nome);
    if (erroNome != null) return SignUpFailure(erroNome);

    final erroCpf = validarCpf(cpf);
    if (erroCpf != null) return SignUpFailure(erroCpf);

    final erroEmail = validarEmail(email);
    if (erroEmail != null) return SignUpFailure(erroEmail);

    final erroSenha = validarSenha(senha);
    if (erroSenha != null) return SignUpFailure(erroSenha);

    try {
      final repository = _ref.read(authRepositoryProvider);
      final resultado = await repository.signUp(
        nome: nome.trim(),
        cpf: cpf.replaceAll(RegExp(r'[^0-9]'), ''),
        email: email.trim(),
        senha: senha,
      );
      return resultado.sessaoCriada
          ? const SignUpSuccess()
          : const SignUpEmailConfirmationRequired();
    } catch (e) {
      // AuthRepositorySupabase embrulha o erro original em AppException
      // (ver auth_error_mapper.dart) — traduzimos a CAUSA real (
      // PostgrestException/AuthException/SocketException), nunca o
      // wrapper, senão `traduzirErroSupabase` nunca reconheceria nada.
      final causa = e is AppException ? (e.cause ?? e) : e;
      return SignUpFailure(traduzirErroSupabase(causa));
    }
  }
}
