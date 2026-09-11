import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/utils/postgrest_filter.dart';

void main() {
  test('valor simples fica entre aspas duplas', () {
    expect(postgrestFilterValue('%getec%'), '"%getec%"');
  });

  test('vírgula (separador de condições do or=) não quebra o filtro', () {
    expect(postgrestFilterValue('a,b'), '"a,b"');
  });

  test('parênteses (agrupamento do or=) não quebram o filtro', () {
    expect(postgrestFilterValue('(a)'), '"(a)"');
  });

  test('aspas duplas no valor são escapadas', () {
    expect(postgrestFilterValue('a"b'), r'"a\"b"');
  });

  test('barra invertida no valor é escapada', () {
    expect(postgrestFilterValue(r'a\b'), r'"a\\b"');
  });
}
