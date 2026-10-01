import 'package:flutter/material.dart';

import '../utils/setor_display.dart';

/// Widget ÚNICO de apresentação compacta de um setor/gerência (PROMPT
/// 11.3.5.4) — reaproveitado em toda tela que mostra um setor num contexto
/// apertado (célula de tabela, dropdown, resumo/detalhamento): mostra a
/// SIGLA cadastrada quando existe, com o NOME COMPLETO disponível por
/// `Tooltip` no hover; cai para o nome completo (sem tooltip redundante,
/// já que o texto visível já É o nome completo) quando não há sigla.
///
/// Nunca decide o valor REAL de nenhum filtro/formulário — é só
/// apresentação; quem usa continua enviando `setor.id` para a lógica.
class SetorCompactText extends StatelessWidget {
  const SetorCompactText({
    super.key,
    required this.nome,
    this.sigla,
    this.style,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines,
    this.fallback = '—',
  });

  final String? nome;
  final String? sigla;
  final TextStyle? style;
  final TextOverflow overflow;
  final int? maxLines;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final texto = siglaOuNomeSetor(sigla: sigla, nome: nome) ?? fallback;
    final nomeAparado = nome?.trim();
    // Só mostra tooltip quando o texto visível é de fato uma ABREVIAÇÃO do
    // nome (a sigla) — evitar um tooltip que repete o próprio texto já
    // visível (quando cai no fallback do nome completo).
    final mostrandoSigla = texto != nomeAparado && nomeAparado != null && nomeAparado.isNotEmpty;

    final textWidget = Text(texto, style: style, overflow: overflow, maxLines: maxLines);
    if (!mostrandoSigla) return textWidget;
    return Tooltip(message: nomeAparado, child: textWidget);
  }
}
