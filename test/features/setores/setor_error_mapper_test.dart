import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/setores/data/setor_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapSetorErrorMessage', () {
    test('nome duplicado (unique constraint setores_nome_key)', () {
      expect(
        mapSetorErrorMessage(
          const PostgrestException(
            message:
                'duplicate key value violates unique constraint '
                '"setores_nome_key"',
            code: '23505',
          ),
        ),
        'Já existe um setor com este nome.',
      );
    });

    test('sigla duplicada (unique constraint setores_sigla_key)', () {
      expect(
        mapSetorErrorMessage(
          const PostgrestException(
            message:
                'duplicate key value violates unique constraint '
                '"setores_sigla_key"',
            code: '23505',
          ),
        ),
        'Já existe um setor com esta sigla.',
      );
    });

    test('setor em uso ao tentar desativar (trigger P0001)', () {
      expect(
        mapSetorErrorMessage(
          const PostgrestException(
            message:
                'Não é possível desativar o setor "GETEC": há 3 '
                'patrimônio(s) não baixado(s) vinculado(s) a ele',
            code: 'P0001',
          ),
        ),
        'Este setor possui patrimônios vinculados e não pode ser desativado.',
      );
    });

    test('sem permissão (RLS nega insert/update)', () {
      expect(
        mapSetorErrorMessage(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
        ),
        'Você não possui permissão para realizar esta operação.',
      );
    });

    test('erro do Postgrest desconhecido cai no fallback genérico', () {
      expect(
        mapSetorErrorMessage(
          const PostgrestException(message: 'algo inesperado', code: '99999'),
        ),
        'Não foi possível completar a operação. Tente novamente.',
      );
    });

    test('erro de conexão', () {
      expect(
        mapSetorErrorMessage(const SocketException('Failed host lookup')),
        'Não foi possível acessar os setores. Tente novamente.',
      );
    });

    test('erro totalmente inesperado cai no fallback genérico', () {
      expect(mapSetorErrorMessage(Exception('boom')), 'Erro inesperado. Tente novamente.');
    });
  });
}
