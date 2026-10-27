import 'patrimonio.dart';

/// Nome da RPC usada por `PatrimonioRepository.cadastrarLote` — mesma
/// convenção de `operacaoAplicarDecisaoComparacao`/`operacaoRetificarUnidade`:
/// uma constante pública, nunca uma string literal espalhada pelo código.
const operacaoCadastrarPatrimonioLote = 'cadastrar_patrimonio_lote';

/// Resultado de `PatrimonioRepository.cadastrarLote` — espelha o jsonb
/// devolvido pela RPC `cadastrar_patrimonio_lote`:
/// `{"patrimonio": {...linha completa de patrimonios...}, "ja_executado":
/// bool}`. [jaExecutado] `true` significa que o `operacaoId` enviado já
/// tinha sido processado antes (retry seguro — nunca uma segunda escrita);
/// [patrimonio] é, nesse caso, o que já existia, não um novo.
class ResultadoCadastroLote {
  const ResultadoCadastroLote({required this.patrimonio, required this.jaExecutado});

  factory ResultadoCadastroLote.fromJson(Map<String, dynamic> json) => ResultadoCadastroLote(
    patrimonio: Patrimonio.fromJson(json['patrimonio'] as Map<String, dynamic>),
    jaExecutado: json['ja_executado'] as bool? ?? false,
  );

  final Patrimonio patrimonio;
  final bool jaExecutado;
}
