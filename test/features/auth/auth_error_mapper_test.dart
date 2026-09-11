import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapAuthErrorMessage', () {
    test('credenciais inválidas (mensagem padrão do GoTrue)', () {
      expect(
        mapAuthErrorMessage(const AuthException('Invalid login credentials')),
        'E-mail ou senha inválidos.',
      );
    });

    test('credenciais inválidas (via código)', () {
      expect(
        mapAuthErrorMessage(
          const AuthException('erro genérico', code: 'invalid_credentials'),
        ),
        'E-mail ou senha inválidos.',
      );
    });

    test('email não confirmado', () {
      expect(
        mapAuthErrorMessage(
          const AuthException(
            'Email not confirmed',
            code: 'email_not_confirmed',
          ),
        ),
        'E-mail ainda não confirmado. Entre em contato com um administrador.',
      );
    });

    test('erro de autenticação desconhecido cai no fallback genérico', () {
      expect(
        mapAuthErrorMessage(const AuthException('algo novo do gotrue')),
        'Não foi possível entrar. Tente novamente.',
      );
    });

    test('falha de rede ao tentar autenticar', () {
      expect(
        mapAuthErrorMessage(AuthRetryableFetchException()),
        'Sem conexão com o servidor. Verifique sua internet.',
      );
    });

    test('SocketException genérica', () {
      expect(
        mapAuthErrorMessage(const SocketException('Failed host lookup')),
        'Sem conexão com o servidor. Verifique sua internet.',
      );
    });

    test('erro totalmente inesperado cai no fallback genérico', () {
      expect(
        mapAuthErrorMessage(Exception('boom')),
        'Erro inesperado. Tente novamente.',
      );
    });
  });
}
