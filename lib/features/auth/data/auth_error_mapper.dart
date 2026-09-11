import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Converte um erro técnico de autenticação em uma mensagem segura para
/// exibir ao usuário, em português. Nunca repassa o texto original do
/// Supabase (evita vazar detalhes técnicos/de infraestrutura).
String mapAuthErrorMessage(Object error) {
  if (error is AuthRetryableFetchException) {
    return 'Sem conexão com o servidor. Verifique sua internet.';
  }

  if (error is AuthException) {
    switch (error.code) {
      case 'email_not_confirmed':
        return 'E-mail ainda não confirmado. Entre em contato com um administrador.';
      case 'user_not_found':
      case 'invalid_credentials':
        return 'E-mail ou senha inválidos.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Muitas tentativas. Aguarde alguns instantes e tente novamente.';
    }

    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials') ||
        message.contains('invalid email or password')) {
      return 'E-mail ou senha inválidos.';
    }
    if (message.contains('email not confirmed')) {
      return 'E-mail ainda não confirmado. Entre em contato com um administrador.';
    }
    return 'Não foi possível entrar. Tente novamente.';
  }

  if (error is SocketException) {
    return 'Sem conexão com o servidor. Verifique sua internet.';
  }

  return 'Erro inesperado. Tente novamente.';
}
