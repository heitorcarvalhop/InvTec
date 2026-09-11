import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Converte um erro técnico de acesso a `patrimonios`/`cadastrar_patrimonio`
/// em uma mensagem segura para exibir ao usuário, em português. Nunca
/// repassa `PostgrestException`/SQLSTATE/stack trace — ver as mensagens e
/// errcodes reais lançados por `cadastrar_patrimonio` e pela trigger
/// `validate_tipo_patrimonio_ativo` em docs/database.md.
String mapPatrimonioErrorMessage(Object error) {
  if (error is PostgrestException) {
    final message = error.message.toLowerCase();

    if (error.code == '23505') {
      return 'Já existe um patrimônio com este número.';
    }

    if (message.contains('tipo de patrimônio inexistente ou inativo')) {
      return 'O tipo de patrimônio selecionado não está mais ativo.';
    }
    if (message.contains('setor de destino inexistente ou inativo')) {
      return 'O setor selecionado não está mais ativo.';
    }
    if (message.contains('setor de origem não encontrado') ||
        message.contains(
          'origem e destino não podem ser o mesmo setor',
        )) {
      return 'Verifique a origem e o destino informados.';
    }
    if (message.contains('não pode estar no futuro')) {
      return 'A data da movimentação não pode estar no futuro.';
    }
    if (message.contains('tipo_id e destino_id são obrigatórios')) {
      return 'Selecione o tipo e o setor de destino.';
    }

    if (error.code == '42501') {
      return 'Você não possui permissão para realizar esta operação.';
    }

    return 'Não foi possível completar a operação. Tente novamente.';
  }

  if (error is SocketException) {
    return 'Não foi possível acessar os patrimônios. Tente novamente.';
  }

  return 'Erro inesperado. Tente novamente.';
}
