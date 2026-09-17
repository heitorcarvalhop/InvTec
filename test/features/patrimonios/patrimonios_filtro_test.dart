import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_filtro.dart';

void main() {
  group('intervaloDeDataValido (PROMPT 9.2, seção 5)', () {
    test('data inicial antes da final: válido', () {
      expect(intervaloDeDataValido(DateTime(2026, 9, 1), DateTime(2026, 9, 16)), isTrue);
    });

    test('data inicial igual à final: válido (limites inclusivos)', () {
      expect(intervaloDeDataValido(DateTime(2026, 9, 1), DateTime(2026, 9, 1)), isTrue);
    });

    test('data inicial depois da final: inválido', () {
      expect(intervaloDeDataValido(DateTime(2026, 9, 16), DateTime(2026, 9, 1)), isFalse);
    });

    test('só data inicial (intervalo aberto): válido', () {
      expect(intervaloDeDataValido(DateTime(2026, 9, 1), null), isTrue);
    });

    test('só data final (intervalo aberto): válido', () {
      expect(intervaloDeDataValido(null, DateTime(2026, 9, 1)), isTrue);
    });

    test('nenhuma data: válido', () {
      expect(intervaloDeDataValido(null, null), isTrue);
    });
  });

  group('PatrimoniosFiltro.quantidadeFiltrosAvancados', () {
    test('nenhum filtro avançado ativo: zero', () {
      expect(const PatrimoniosFiltro().quantidadeFiltrosAvancados, 0);
    });

    test('marca + modelo + responsável: três', () {
      final filtro = const PatrimoniosFiltro().copyWith(marca: 'dell', modelo: 'latitude', responsavel: 'heitor');
      expect(filtro.quantidadeFiltrosAvancados, 3);
    });

    test('intervalo de data de cadastro (De + Até) conta como UM filtro, não dois', () {
      final filtro = const PatrimoniosFiltro().copyWith(
        dataCadastroDe: DateTime(2026, 9, 1),
        dataCadastroAte: DateTime(2026, 9, 16),
      );
      expect(filtro.quantidadeFiltrosAvancados, 1);
    });

    test('data de cadastro + data de aquisição: dois filtros', () {
      final filtro = const PatrimoniosFiltro().copyWith(
        dataCadastroDe: DateTime(2026, 9, 1),
        dataAquisicaoAte: DateTime(2026, 9, 16),
      );
      expect(filtro.quantidadeFiltrosAvancados, 2);
    });
  });
}
