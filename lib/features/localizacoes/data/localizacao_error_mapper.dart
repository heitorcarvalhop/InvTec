import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Converte um erro técnico de acesso a `localizacoes` em uma mensagem
/// segura para exibir ao usuário, em português. Nunca repassa
/// `PostgrestException`/SQLSTATE/stack trace.
String mapLocalizacaoErrorMessage(Object error) {
  if (error is PostgrestException) {
    final message = error.message.toLowerCase();

    if (error.code == '23505') {
      if (message.contains('localizacoes_setor_sigla_key')) {
        return 'Já existe uma localização com esta sigla nesta gerência.';
      }
      if (message.contains('localizacoes_setor_nome_key')) {
        return 'Já existe uma localização com este nome nesta gerência.';
      }
      return 'Já existe uma localização com esses dados nesta gerência.';
    }

    // Trigger private.prevent_deactivate_localizacao_em_uso (errcode P0001).
    if (message.contains('não é possível desativar a localização')) {
      return 'Esta localização possui patrimônios vinculados e não pode ser desativada.';
    }

    // Trigger private.validate_setor_ativo_para_localizacao (errcode P0001).
    if (message.contains('gerência inexistente ou inativa')) {
      return 'Não é possível criar ou reativar uma localização em uma gerência inativa.';
    }

    // Trigger public.protect_localizacao_setor (errcode 42501).
    if (message.contains('gerência de uma localização não pode ser alterada')) {
      return 'A gerência de uma localização não pode ser alterada. Desative-a e crie uma nova na gerência correta.';
    }

    // RLS/policy negou a operação (INSERT/UPDATE fora de ADMIN/GESTOR).
    if (error.code == '42501') {
      return 'Você não possui permissão para realizar esta operação.';
    }

    return 'Não foi possível completar a operação. Tente novamente.';
  }

  if (error is SocketException) {
    return 'Não foi possível acessar as localizações. Tente novamente.';
  }

  return 'Erro inesperado. Tente novamente.';
}
