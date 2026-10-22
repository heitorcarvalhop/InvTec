import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/tombamento_normalizacao.dart';

/// Reimplementação em Dart EXATA do algoritmo de
/// `public.normalizar_tombamento_chave` (SQL, Fase 3A —
/// supabase/migrations/20261014100000_add_patrimonio_tombamento_historico.sql),
/// linha por linha:
///
/// ```sql
/// if p_valor is null then return null; end if;
/// v_valor := trim(p_valor);
/// if v_valor = '' then return null; end if;
/// if v_valor !~ '^[0-9]+$' then return upper(v_valor); end if;
/// v_sem_zeros := regexp_replace(v_valor, '^0+', '');
/// if v_sem_zeros = '' then return null; end if;
/// return v_sem_zeros;
/// ```
///
/// Este teste NÃO executa SQL (nenhum SQL foi executado nesta fase, por
/// instrução explícita) — ele prova que, SE esse algoritmo for executado
/// no Postgres exatamente como escrito, produz a MESMA chave de
/// comparação que [normalizarTombamentoParaComparacao] (já testada na
/// Fase 1) para a mesma bateria de valores. É a forma de "testar" a
/// lógica SQL localmente sem uma conexão real com o banco.
String? _chaveSegundoSql(String? valor) {
  if (valor == null) return null;
  final v = valor.trim();
  if (v.isEmpty) return null;
  if (!RegExp(r'^[0-9]+$').hasMatch(v)) return v.toUpperCase();
  final semZeros = v.replaceFirst(RegExp(r'^0+'), '');
  if (semZeros.isEmpty) return null;
  return semZeros;
}

void main() {
  group(
    'Paridade SQL ↔ Dart — normalizar_tombamento_chave vs normalizarTombamentoParaComparacao',
    () {
      const casos = <String?>[
        '000123456',
        '00123456',
        '123456',
        '000504797',
        '003636971',
        '000000001',
        '001020304', // zero interno
        '000123400', // zero final
        '0', '00', '000000', // só zeros
        '', '   ', // vazio
        'TI-769', 'ti-769', // não numérico
        '0859312', '859312', // exemplo real da Fase 2 (candidato a histórico)
      ];

      for (final caso in casos) {
        test('"${caso ?? "null"}" produz a mesma chave nos dois lados', () {
          final chaveDart = normalizarTombamentoParaComparacao(
            caso,
          ).chaveComparacao;
          final chaveSql = _chaveSegundoSql(caso);
          expect(chaveSql, chaveDart, reason: 'entrada: ${caso ?? "null"}');
        });
      }

      test('null produz a mesma chave (null) nos dois lados', () {
        expect(
          _chaveSegundoSql(null),
          normalizarTombamentoParaComparacao(null).chaveComparacao,
        );
      });
    },
  );
}
