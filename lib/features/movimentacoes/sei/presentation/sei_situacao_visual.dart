import 'package:flutter/material.dart';

import '../../../../core/widgets/status_chip.dart';
import '../domain/sei_documento_situacao.dart';
import '../domain/sei_item_pendencia_status.dart';

/// Ícone + categoria semântica por situação geral de documento — mesma
/// linguagem visual de `visualDoStatusSei`.
(IconData, AppStatusKind) visualDaSituacaoDocumentoSei(SeiDocumentoSituacao situacao) {
  return switch (situacao) {
    SeiDocumentoSituacao.pendente => (Icons.hourglass_empty, AppStatusKind.warning),
    SeiDocumentoSituacao.parcialmenteConcluido => (Icons.incomplete_circle, AppStatusKind.info),
    SeiDocumentoSituacao.concluido => (Icons.check_circle_outline, AppStatusKind.success),
    SeiDocumentoSituacao.cancelado => (Icons.cancel_outlined, AppStatusKind.neutral),
    SeiDocumentoSituacao.encerradoParcialmente => (Icons.fact_check_outlined, AppStatusKind.info),
  };
}

(IconData, AppStatusKind) visualDoStatusItemPendencia(SeiItemPendenciaStatus status) {
  return switch (status) {
    SeiItemPendenciaStatus.pendente => (Icons.hourglass_empty, AppStatusKind.warning),
    SeiItemPendenciaStatus.concluido => (Icons.check_circle_outline, AppStatusKind.success),
    SeiItemPendenciaStatus.cancelado => (Icons.cancel_outlined, AppStatusKind.neutral),
  };
}
