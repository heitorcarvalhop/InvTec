import 'package:flutter/material.dart';

import '../../../../core/widgets/status_chip.dart';
import '../domain/sei_validacao_item.dart';

/// Ícone, categoria semântica e rótulo por status de linha (PROMPT 11.1,
/// seção 33: "pronto → sucesso, aviso → warning, bloqueado → erro") — um
/// único lugar para a tabela de prévia e o detalhe da linha usarem a mesma
/// linguagem visual.
(IconData, AppStatusKind, String) visualDoStatusSei(SeiStatusLinha status) {
  return switch (status) {
    SeiStatusLinha.pronto => (Icons.check_circle_outline, AppStatusKind.success, 'Pronto'),
    SeiStatusLinha.aviso => (Icons.warning_amber_outlined, AppStatusKind.warning, 'Aviso'),
    SeiStatusLinha.bloqueado => (Icons.block, AppStatusKind.error, 'Bloqueado'),
  };
}
