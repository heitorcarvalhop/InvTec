import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Converte um erro técnico de `registrar_movimentacao` em uma mensagem
/// segura para exibir ao usuário, em português. Nunca repassa
/// `PostgrestException`/SQLSTATE/stack trace — ver as mensagens e errcodes
/// reais lançados pela RPC em
/// supabase/migrations/20260914140000_add_localizacoes.sql (seção 8) e em
/// docs/database.md.
String mapMovimentacaoErrorMessage(Object error) {
  if (error is PostgrestException) {
    final message = error.message.toLowerCase();

    if (error.code == '42501' || message.contains('sem permissão')) {
      return 'Você não possui permissão para registrar movimentações.';
    }
    if (message.contains('patrimônio') && message.contains('não encontrado')) {
      return 'Este patrimônio não foi encontrado — ele pode ter sido removido ou alterado.';
    }
    if (message.contains('não é permitida para patrimônio com status')) {
      return 'Esta movimentação não é mais permitida para o estado atual do patrimônio. '
          'Feche e reabra o formulário para ver o estado mais recente.';
    }
    if (message.contains('é anterior à última movimentação')) {
      return 'A data informada é anterior à última movimentação já registrada para este patrimônio.';
    }
    if (message.contains('não pode estar no futuro')) {
      return 'A data da movimentação não pode estar no futuro.';
    }
    if (message.contains('movimentação interna') && message.contains('localizacao_destino_id')) {
      return 'Movimentação interna (mesmo setor) exige uma localização de destino.';
    }
    if (message.contains('localização de destino precisa ser diferente')) {
      return 'A localização de destino precisa ser diferente da localização atual.';
    }
    if (message.contains('destino igual ao setor atual')) {
      return 'O destino selecionado é igual ao setor atual do patrimônio.';
    }
    if (message.contains('exige destino_id')) {
      return 'Selecione o setor de destino.';
    }
    if (message.contains('baixa não aceita')) {
      return 'Baixa não aceita destino, localização ou responsável — apenas motivo, documento e observação.';
    }
    if (message.contains('ajuste_inventario não altera o responsável')) {
      return 'Ajuste de inventário não pode alterar o responsável.';
    }
    if (message.contains('patrimônio baixado não pode mudar de setor')) {
      return 'Este patrimônio está baixado e não pode mudar de setor.';
    }
    if (message.contains('patrimônio baixado não pode mudar de localização')) {
      return 'Este patrimônio está baixado e não pode mudar de localização.';
    }
    if (message.contains('patrimônio baixado não pode limpar a localização')) {
      return 'Este patrimônio está baixado e não pode limpar a localização.';
    }
    if (message.contains('alteracao_responsavel não aceita destino_id')) {
      return 'Alteração de responsável não altera o setor.';
    }
    if (message.contains('alteracao_responsavel não aceita localizacao_destino_id')) {
      return 'Alteração de responsável não altera a localização.';
    }
    if (message.contains('alteracao_responsavel exige responsavel_destino')) {
      return 'Informe o novo responsável.';
    }
    if (message.contains('novo responsável deve ser diferente')) {
      return 'O novo responsável deve ser diferente do responsável atual.';
    }
    if (message.contains('emprestimo exige responsavel_destino')) {
      return 'Informe o responsável pelo empréstimo.';
    }
    if (message.contains('setor de destino inexistente ou inativo')) {
      return 'O setor de destino selecionado não está mais ativo.';
    }
    if (message.contains('localização de destino não encontrada')) {
      return 'A localização de destino selecionada não foi encontrada.';
    }
    if (message.contains('localização de destino inativa')) {
      return 'A localização de destino selecionada não está mais ativa.';
    }
    if (message.contains('não pertence ao setor de destino')) {
      return 'A localização selecionada não pertence ao setor de destino.';
    }
    if (message.contains('limpar_localizacao só é permitido')) {
      return 'Limpar a localização só é permitido em Ajuste de inventário.';
    }
    if (message.contains('localizacao_destino_id não podem ser usados juntos')) {
      return 'Escolha uma nova localização OU marque para limpar — não os dois ao mesmo tempo.';
    }
    if (message.contains('patrimonio_id e tipo são obrigatórios')) {
      return 'Selecione o patrimônio e o tipo de movimentação.';
    }

    return 'Não foi possível registrar a movimentação. Tente novamente.';
  }

  if (error is SocketException) {
    return 'Não foi possível registrar a movimentação. Verifique sua conexão e tente novamente.';
  }

  return 'Erro inesperado. Tente novamente.';
}
