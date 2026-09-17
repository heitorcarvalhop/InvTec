import 'patrimonio.dart';

/// [Patrimonio] com os nomes já resolvidos (tipo, setor atual e, quando
/// disponível, quem cadastrou) — evita mostrar UUID na tela e evita uma
/// consulta extra por linha (os nomes vêm via embed do Postgrest).
///
/// Usado tanto na listagem quanto no detalhe; [criadoPorNome] só é
/// preenchido no detalhe (a listagem não embute `profiles` — não é exibido
/// lá e reduziria o join sem necessidade). Pode ficar nulo mesmo no
/// detalhe: a policy de `profiles` só deixa ADMIN/GESTOR verem o nome de
/// quem não é o próprio usuário (ver docs/database.md) — quando a RLS
/// nega, o embed volta nulo e a UI simplesmente omite a informação.
class PatrimonioDetalhe {
  const PatrimonioDetalhe({
    required this.patrimonio,
    required this.tipoNome,
    required this.setorNome,
    this.localizacaoNome,
    this.criadoPorNome,
  });

  factory PatrimonioDetalhe.fromJson(Map<String, dynamic> json) {
    final tipo = json['tipos_patrimonio'] as Map<String, dynamic>?;
    final setor = json['setores'] as Map<String, dynamic>?;
    final localizacao = json['localizacoes'] as Map<String, dynamic>?;
    final criador = json['criado_por_profile'] as Map<String, dynamic>?;

    return PatrimonioDetalhe(
      patrimonio: Patrimonio.fromJson(json),
      tipoNome: (tipo?['nome'] as String?) ?? 'Tipo não encontrado',
      setorNome: (setor?['nome'] as String?) ?? 'Setor não encontrado',
      // null é um estado válido (localização é opcional) — só vira "Não
      // encontrada" quando havia um id mas o embed não resolveu (ex.: RLS).
      localizacaoNome: localizacao?['nome'] as String?,
      criadoPorNome: criador?['nome'] as String?,
    );
  }

  final Patrimonio patrimonio;
  final String tipoNome;
  final String setorNome;
  final String? localizacaoNome;
  final String? criadoPorNome;
}
