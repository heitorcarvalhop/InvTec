import 'package:flutter/material.dart';

/// Diálogo "Descartar alterações?" — usado por qualquer fluxo deste domínio
/// que tenha entrada de dados do usuário antes de sair sem salvar (o
/// formulário de cadastro de patrimônio e o assistente de importação).
/// Nunca duplicar esta lógica: sempre chamar esta função a partir de ambos
/// os pontos de saída de um mesmo fluxo (botão de cabeçalho e botão de
/// rodapé, por exemplo).
///
/// Retorna `true` somente quando o usuário escolhe explicitamente
/// "Descartar"; `false` para "Continuar editando" ou para o diálogo
/// fechado de qualquer outra forma (ex.: Esc).
Future<bool> confirmarDescartarAlteracoes(
  BuildContext context, {
  String title = 'Descartar alterações?',
  String message = 'Os dados preenchidos ainda não foram salvos e serão perdidos.',
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Continuar editando'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Descartar'),
        ),
      ],
    ),
  );
  return resultado ?? false;
}
