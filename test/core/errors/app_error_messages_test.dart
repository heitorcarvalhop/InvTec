import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('traduzirErroSupabase', () {
    test('mensagem amigável pronta de uma RPC administrativa (P0001) é repassada', () {
      const erro = PostgrestException(
        message: 'Não é possível remover o último administrador ativo do sistema',
        code: 'P0001',
      );
      expect(
        traduzirErroSupabase(erro),
        'Não é possível remover o último administrador ativo do sistema',
      );
    });

    test('mensagem amigável pronta por falta de permissão (42501) é repassada', () {
      const erro = PostgrestException(
        message: 'Apenas administradores podem aprovar usuários',
        code: '42501',
      );
      expect(traduzirErroSupabase(erro), 'Apenas administradores podem aprovar usuários');
    });

    test('mensagem amigável pronta de "usuário não encontrado" (P0002) é repassada', () {
      const erro = PostgrestException(message: 'Usuário não encontrado', code: 'P0002');
      expect(traduzirErroSupabase(erro), 'Usuário não encontrado');
    });

    test('mensagem amigável pronta de CPF em uso (P0021) é repassada', () {
      const erro = PostgrestException(
        message: 'CPF já está em uso por outro usuário',
        code: 'P0021',
      );
      expect(traduzirErroSupabase(erro), 'CPF já está em uso por outro usuário');
    });

    test('unique_violation (23505) vira mensagem neutra de cadastro duplicado', () {
      const erro = PostgrestException(message: 'duplicate key value violates unique constraint "profiles_cpf_key"', code: '23505');
      expect(
        traduzirErroSupabase(erro),
        'Não foi possível concluir o cadastro. Verifique se os dados informados já estão associados a uma conta.',
      );
    });

    test('código reconhecido mas mensagem crua (SQLSTATE puro) cai no fallback genérico', () {
      const erro = PostgrestException(message: '42501', code: 'P0001');
      expect(
        traduzirErroSupabase(erro),
        'Não foi possível concluir a operação. Tente novamente em alguns instantes.',
      );
    });

    test('código não reconhecido cai no fallback genérico', () {
      const erro = PostgrestException(message: 'algo obscuro', code: '99999');
      expect(
        traduzirErroSupabase(erro),
        'Não foi possível concluir a operação. Tente novamente em alguns instantes.',
      );
    });

    test('AuthException "already registered" vira mensagem neutra de cadastro duplicado', () {
      const erro = AuthException('User already registered');
      expect(
        traduzirErroSupabase(erro),
        'Não foi possível concluir o cadastro. Verifique se os dados informados já estão associados a uma conta.',
      );
    });

    test('AuthException genérica cai no fallback genérico', () {
      const erro = AuthException('algo inesperado do gotrue');
      expect(
        traduzirErroSupabase(erro),
        'Não foi possível concluir a operação. Tente novamente em alguns instantes.',
      );
    });

    test('falha de rede (AuthRetryableFetchException) vira mensagem de conexão', () {
      expect(
        traduzirErroSupabase(AuthRetryableFetchException()),
        'Não foi possível conectar. Verifique sua conexão e tente novamente.',
      );
    });

    test('SocketException vira mensagem de conexão', () {
      expect(
        traduzirErroSupabase(const SocketException('Failed host lookup')),
        'Não foi possível conectar. Verifique sua conexão e tente novamente.',
      );
    });

    test('erro totalmente inesperado cai no fallback genérico, nunca expõe o texto bruto', () {
      final mensagem = traduzirErroSupabase(Exception('stack trace sensível XYZ'));
      expect(mensagem, 'Não foi possível concluir a operação. Tente novamente em alguns instantes.');
      expect(mensagem.contains('XYZ'), isFalse);
    });
  });
}
