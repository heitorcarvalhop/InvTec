import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Cabeçalho padrão de página: título + subtítulo + ações à direita (que
/// quebram para baixo do título em telas estreitas) — PROMPT 9.3. Usado em
/// toda página de listagem/gestão para nunca haver dois estilos de
/// cabeçalho diferentes na aplicação.
class InvTecPageHeader extends StatelessWidget {
  const InvTecPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Telas estreitas: título e ações empilham em vez de ficar lado a lado.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTypography.pageTitle(context)),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle!, style: AppTypography.pageSubtitle(context)),
        ],
      ],
    );

    if (actions.isEmpty) return titulo;

    final botoes = Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions);

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titulo, const SizedBox(height: AppSpacing.md), botoes],
      );
    }

    // PROMPT 11.3.9.1 — nunca mais um `Row` aqui: `botoes` (um `Wrap`) não é
    // flexível, então um `Row` dava a ele sua largura NATURAL irrestrita
    // (soma dos dois botões) já na primeira passada de layout — em telas
    // de tablet (600–1024px, onde `compact` continua `false`), essa largura
    // fixa sobrava pouco ou nenhum espaço para o `Expanded(child: titulo)`,
    // que ficava espremido a zero/largura negativa: o título quebrava
    // letra por letra e o próprio `Row` estourava ("RenderFlex overflowed
    // ... on the right" — exatamente os erros do vídeo). Um `Wrap` nunca
    // esmaga um item abaixo do tamanho natural dele — quando título e
    // botões não cabem lado a lado, os botões simplesmente descem para uma
    // nova linha inteira, nunca uma letra por linha. `SizedBox(width:
    // double.infinity)` é necessário: um `Wrap` sem largura própria imposta
    // encolhe para o conteúdo (confirmado empiricamente) — sem isso,
    // `WrapAlignment.spaceBetween` não teria espaço sobrando para distribuir
    // e os botões ficariam colados ao título, nunca no canto direito como
    // hoje.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        runSpacing: AppSpacing.md,
        children: [titulo, botoes],
      ),
    );
  }
}
