import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio_repository.dart';

class FakeTipoPatrimonioRepository implements TipoPatrimonioRepository {
  FakeTipoPatrimonioRepository({List<TipoPatrimonio>? tipos})
    : _tipos = [...?tipos];

  final List<TipoPatrimonio> _tipos;

  @override
  Future<List<TipoPatrimonio>> listarAtivos() async {
    return _tipos.where((t) => t.ativo).toList();
  }
}
