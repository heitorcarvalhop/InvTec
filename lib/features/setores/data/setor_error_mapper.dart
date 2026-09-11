import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Converte um erro técnico de acesso a `setores` em uma mensagem segura
/// para exibir ao usuário, em português. Nunca repassa
/// `PostgrestException`/SQLSTATE/stack trace (ver docs/database.md para as
/// constraints e a trigger que originam esses erros).
String mapSetorErrorMessage(Object error) {
  if (error is PostgrestException) {
    final message = error.message.toLowerCase();

    if (error.code == '23505') {
      if (message.contains('setores_sigla_key')) {
        return 'Já existe um setor com esta sigla.';
      }
      if (message.contains('setores_nome_key')) {
        return 'Já existe um setor com este nome.';
      }
      return 'Já existe um setor com esses dados.';
    }

    // Trigger private.prevent_deactivate_setor_em_uso (errcode P0001).
    if (message.contains('não é possível desativar o setor')) {
      return 'Este setor possui patrimônios vinculados e não pode ser desativado.';
    }

    // RLS/policy negou a operação (INSERT/UPDATE fora de ADMIN/GESTOR).
    if (error.code == '42501') {
      return 'Você não possui permissão para realizar esta operação.';
    }

    return 'Não foi possível completar a operação. Tente novamente.';
  }

  if (error is SocketException) {
    return 'Não foi possível acessar os setores. Tente novamente.';
  }

  return 'Erro inesperado. Tente novamente.';
}
