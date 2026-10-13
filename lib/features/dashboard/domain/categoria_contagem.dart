/// Uma categoria (setor, tipo de patrimônio ou localização) e quantas
/// vezes ela aparece como `setor_atual_id`/`tipo_id`/`localizacao_atual_id`
/// de algum patrimônio — usado pelas seções "Patrimônios por setor",
/// "Patrimônios por tipo" e "Locais com mais patrimônios" do Dashboard.
class CategoriaContagem {
  const CategoriaContagem({
    required this.id,
    required this.nome,
    required this.quantidade,
    this.subtitulo,
  });

  final String id;
  final String nome;
  final int quantidade;

  /// Texto discreto opcional abaixo do nome (ex.: sigla do setor-pai de uma
  /// localização). `null` quando não houver nada a mostrar.
  final String? subtitulo;
}
