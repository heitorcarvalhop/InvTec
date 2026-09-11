import 'tipo_patrimonio.dart';

abstract class TipoPatrimonioRepository {
  /// Tipos ativos, usados em seletores/formulários de cadastro.
  Future<List<TipoPatrimonio>> listarAtivos();
}
