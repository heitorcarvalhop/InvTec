import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapPatrimonioErrorMessage', () {
    test('número patrimonial duplicado (RPC, errcode 23505)', () {
      expect(
        mapPatrimonioErrorMessage(
          const PostgrestException(
            message: 'Já existe um patrimônio com o número 00045872',
            code: '23505',
          ),
        ),
        'Já existe um patrimônio com este número.',
      );
    });

    test('tipo inativo/inexistente', () {
      expect(
        mapPatrimonioErrorMessage(
          const PostgrestException(
            message: 'Tipo de patrimônio inexistente ou inativo',
            code: 'P0001',
          ),
        ),
        'O tipo de patrimônio selecionado não está mais ativo.',
      );
    });

    test('setor de destino inativo/inexistente', () {
      expect(
        mapPatrimonioErrorMessage(
          const PostgrestException(
            message: 'Setor de destino inexistente ou inativo',
            code: 'P0001',
          ),
        ),
        'O setor selecionado não está mais ativo.',
      );
    });

    test('origem igual ao destino', () {
      expect(
        mapPatrimonioErrorMessage(
          const PostgrestException(
            message:
                'Origem e destino não podem ser o mesmo setor em uma ENTRADA',
            code: 'P0001',
          ),
        ),
        'Verifique a origem e o destino informados.',
      );
    });

    test('setor de origem não encontrado (errcode P0002)', () {
      expect(
        mapPatrimonioErrorMessage(
          const PostgrestException(
            message: 'Setor de origem não encontrado',
            code: 'P0002',
          ),
        ),
        'Verifique a origem e o destino informados.',
      );
    });

    test('data da movimentação no futuro', () {
      expect(
        mapPatrimonioErrorMessage(
          const PostgrestException(
            message: 'data_movimentacao não pode estar no futuro',
            code: 'P0001',
          ),
        ),
        'A data da movimentação não pode estar no futuro.',
      );
    });

    test('sem permissão (RPC ou UPDATE negado pela RLS)', () {
      expect(
        mapPatrimonioErrorMessage(
          const PostgrestException(
            message: 'Usuário sem permissão para cadastrar patrimônio',
            code: '42501',
          ),
        ),
        'Você não possui permissão para realizar esta operação.',
      );
    });

    test('erro de conexão', () {
      expect(
        mapPatrimonioErrorMessage(const SocketException('Failed host lookup')),
        'Não foi possível acessar os patrimônios. Tente novamente.',
      );
    });

    test('erro totalmente inesperado cai no fallback genérico', () {
      expect(
        mapPatrimonioErrorMessage(Exception('boom')),
        'Erro inesperado. Tente novamente.',
      );
    });
  });
}
