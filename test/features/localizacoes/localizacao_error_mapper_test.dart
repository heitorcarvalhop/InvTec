import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/localizacoes/data/localizacao_error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapLocalizacaoErrorMessage', () {
    test('nome duplicado na mesma gerência (unique constraint localizacoes_setor_nome_key)', () {
      expect(
        mapLocalizacaoErrorMessage(
          const PostgrestException(
            message:
                'duplicate key value violates unique constraint '
                '"localizacoes_setor_nome_key"',
            code: '23505',
          ),
        ),
        'Já existe uma localização com este nome nesta gerência.',
      );
    });

    test('sigla duplicada na mesma gerência (unique constraint localizacoes_setor_sigla_key)', () {
      expect(
        mapLocalizacaoErrorMessage(
          const PostgrestException(
            message:
                'duplicate key value violates unique constraint '
                '"localizacoes_setor_sigla_key"',
            code: '23505',
          ),
        ),
        'Já existe uma localização com esta sigla nesta gerência.',
      );
    });

    test('localização em uso ao tentar desativar (trigger P0001)', () {
      expect(
        mapLocalizacaoErrorMessage(
          const PostgrestException(
            message:
                'Não é possível desativar a localização "Home Office": há 2 '
                'patrimônio(s) não baixado(s) vinculado(s) a ela',
            code: 'P0001',
          ),
        ),
        'Esta localização possui patrimônios vinculados e não pode ser desativada.',
      );
    });

    test('gerência não pode ser alterada depois de criada (trigger 42501)', () {
      expect(
        mapLocalizacaoErrorMessage(
          const PostgrestException(
            message:
                'A gerência de uma localização não pode ser alterada depois de '
                'criada. Desative esta localização e crie uma nova na gerência correta.',
            code: '42501',
          ),
        ),
        'A gerência de uma localização não pode ser alterada. Desative-a e crie uma nova na gerência correta.',
      );
    });

    test('criar localização em gerência inativa é rejeitado (trigger P0001)', () {
      expect(
        mapLocalizacaoErrorMessage(
          const PostgrestException(
            message:
                'Não é possível criar ou reativar uma localização em uma '
                'gerência inexistente ou inativa',
            code: 'P0001',
          ),
        ),
        'Não é possível criar ou reativar uma localização em uma gerência inativa.',
      );
    });

    test('reativar localização em gerência inativa é rejeitado (mesma trigger, mesmo P0001)', () {
      // A trigger validate_setor_ativo_para_localizacao dispara igualmente
      // para INSERT e para UPDATE OF ativo (reativação) — mesma mensagem.
      expect(
        mapLocalizacaoErrorMessage(
          const PostgrestException(
            message:
                'Não é possível criar ou reativar uma localização em uma '
                'gerência inexistente ou inativa',
            code: 'P0001',
          ),
        ),
        'Não é possível criar ou reativar uma localização em uma gerência inativa.',
      );
    });

    test('sem permissão (RLS nega insert/update)', () {
      expect(
        mapLocalizacaoErrorMessage(
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
        mapLocalizacaoErrorMessage(
          const PostgrestException(message: 'algo inesperado', code: '99999'),
        ),
        'Não foi possível completar a operação. Tente novamente.',
      );
    });

    test('erro de conexão', () {
      expect(
        mapLocalizacaoErrorMessage(const SocketException('Failed host lookup')),
        'Não foi possível acessar as localizações. Tente novamente.',
      );
    });

    test('erro totalmente inesperado cai no fallback genérico', () {
      expect(mapLocalizacaoErrorMessage(Exception('boom')), 'Erro inesperado. Tente novamente.');
    });
  });
}
