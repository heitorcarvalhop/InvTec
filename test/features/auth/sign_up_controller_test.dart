import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/auth_repository.dart';
import 'package:invtec/features/auth/presentation/sign_up_controller.dart';

import 'fake_auth_repository.dart';

void main() {
  group('SignUpController', () {
    late FakeAuthRepository fakeAuth;
    late ProviderContainer container;

    setUp(() {
      fakeAuth = FakeAuthRepository();
      container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(fakeAuth)],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);
    });

    SignUpController controller() => container.read(signUpControllerProvider);

    test('nome vazio: falha de validação, nunca chama o repositório', () async {
      final outcome = await controller().signUp(
        nome: '',
        cpf: '52998224725',
        email: 'fulano@invtec.com',
        senha: 'Abcdefghij1!',
      );

      expect(outcome, isA<SignUpFailure>());
      expect(fakeAuth.signUpCallCount, 0);
    });

    test('CPF inválido: falha de validação, nunca chama o repositório', () async {
      final outcome = await controller().signUp(
        nome: 'Fulano de Tal',
        cpf: '11111111111',
        email: 'fulano@invtec.com',
        senha: 'Abcdefghij1!',
      );

      expect(outcome, isA<SignUpFailure>());
      expect(fakeAuth.signUpCallCount, 0);
    });

    test('senha fraca: falha de validação, nunca chama o repositório', () async {
      final outcome = await controller().signUp(
        nome: 'Fulano de Tal',
        cpf: '52998224725',
        email: 'fulano@invtec.com',
        senha: 'fraca',
      );

      expect(outcome, isA<SignUpFailure>());
      expect(fakeAuth.signUpCallCount, 0);
    });

    test('e-mail inválido: falha de validação, nunca chama o repositório', () async {
      final outcome = await controller().signUp(
        nome: 'Fulano de Tal',
        cpf: '52998224725',
        email: 'nao-e-email',
        senha: 'Abcdefghij1!',
      );

      expect(outcome, isA<SignUpFailure>());
      expect(fakeAuth.signUpCallCount, 0);
    });

    test('dados válidos + sessão criada: SignUpSuccess, chama o repositório uma vez', () async {
      fakeAuth.signUpResult = const AuthSignUpResult(sessaoCriada: true);

      final outcome = await controller().signUp(
        nome: '  Fulano de Tal  ',
        cpf: '529.982.247-25',
        email: '  fulano@invtec.com  ',
        senha: 'Abcdefghij1!',
      );

      expect(outcome, isA<SignUpSuccess>());
      expect(fakeAuth.signUpCallCount, 1);
    });

    test('dados válidos + confirmação de e-mail exigida: SignUpEmailConfirmationRequired', () async {
      fakeAuth.signUpResult = const AuthSignUpResult(sessaoCriada: false);

      final outcome = await controller().signUp(
        nome: 'Fulano de Tal',
        cpf: '52998224725',
        email: 'fulano@invtec.com',
        senha: 'Abcdefghij1!',
      );

      expect(outcome, isA<SignUpEmailConfirmationRequired>());
    });

    test('erro do servidor (ex.: CPF/e-mail duplicado) vira SignUpFailure com mensagem traduzida', () async {
      fakeAuth.signUpError = Exception('erro bruto do servidor');

      final outcome = await controller().signUp(
        nome: 'Fulano de Tal',
        cpf: '52998224725',
        email: 'fulano@invtec.com',
        senha: 'Abcdefghij1!',
      );

      expect(outcome, isA<SignUpFailure>());
      final failure = outcome as SignUpFailure;
      // Nunca expõe o texto bruto da exceção.
      expect(failure.mensagem.contains('erro bruto'), isFalse);
    });
  });
}
