import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';

import '../../auth/fake_auth_repository.dart';
import 'fake_documentos_sei_repository.dart';

Profile _profile() => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

SeiItemPendente _item({
  required int linha,
  required String origemNome,
  String? origemSigla,
  required String destinoNome,
  String? destinoSigla,
}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: 'doc-1',
    linha: linha,
    numeroPatrimonio: SeiValorCorrigivel(original: '100$linha'),
    origemTexto: SeiValorCorrigivel(original: origemNome),
    origemSetorNome: origemNome,
    origemSetorSigla: origemSigla,
    destinoTexto: SeiValorCorrigivel(original: destinoNome),
    destinoSetorNome: destinoNome,
    destinoSetorSigla: destinoSigla,
    numeroChamado: const SeiValorCorrigivel(original: '4556'),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Monitor'),
    status: SeiItemPendenciaStatus.pendente,
    criadoEm: DateTime(2026, 1, 1),
  );
}

Future<void> _pumpDialogo(WidgetTester tester, SeiDocumentoPendente documento) async {
  final fakeAuth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _profile());
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        documentosSeiRepositoryProvider.overrideWithValue(
          FakeDocumentosSeiRepository(documentosIniciais: [documento]),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSeiPendenciaDetalheDialog(context, documento.id),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('detalhamento do despacho SEI mostra siglas dos setores, não nomes longos', () {
    testWidgets('GETEC/GEASI aparecem como siglas, e o nome completo fica no tooltip', (tester) async {
      final documento = SeiDocumentoPendente.fromItens(
        id: '4006bdf4-6927-444e-912b-0e4d42653500',
        numeroDocumentoSei: '95955192',
        numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
        tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
        nomeArquivo: 'despacho.pdf',
        hashSha256: 'hash',
        versao: 1,
        criadoEm: DateTime(2026, 1, 1),
        criadoPorId: 'user-1',
        criadoPorNome: 'Fulano',
        itens: [
          _item(
            linha: 1,
            origemNome: 'Gerencia de Tecnologia',
            origemSigla: 'GETEC',
            destinoNome:
                'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
            destinoSigla: 'GEASI',
          ),
        ],
      );

      await _pumpDialogo(tester, documento);

      // As colunas mostram a SIGLA, nunca o nome completo com dezenas de
      // caracteres.
      expect(find.text('GETEC'), findsOneWidget);
      expect(find.text('GEASI'), findsOneWidget);
      expect(
        find.text('Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto'),
        findsNothing,
        reason: 'o nome completo não deve aparecer diretamente na célula da tabela',
      );

      // O nome completo continua acessível — via Tooltip.
      final tooltipDestino = tester.widget<Tooltip>(
        find.ancestor(of: find.text('GEASI'), matching: find.byType(Tooltip)).first,
      );
      expect(
        tooltipDestino.message,
        'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
      );
    });

    testWidgets('GESOL e CIMEHGO também aparecem como sigla', (tester) async {
      final documento = SeiDocumentoPendente.fromItens(
        id: 'doc-2',
        numeroDocumentoSei: '11111111',
        tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
        nomeArquivo: 'despacho2.pdf',
        hashSha256: 'hash2',
        versao: 1,
        criadoEm: DateTime(2026, 1, 1),
        criadoPorId: 'user-1',
        criadoPorNome: 'Fulano',
        itens: [
          _item(
            linha: 1,
            origemNome:
                'Gerência de Licenciamento de Atividades Agropecuárias e de Conversão do Uso do Solo',
            origemSigla: 'GESOL',
            destinoNome: 'Centro de Informações Meteorológicas e Hidrológicas de Goiás',
            destinoSigla: 'CIMEHGO',
          ),
        ],
      );

      await _pumpDialogo(tester, documento);

      expect(find.text('GESOL'), findsOneWidget);
      expect(find.text('CIMEHGO'), findsOneWidget);
    });

    testWidgets('setor sem sigla cadastrada cai para o nome completo (fallback seguro)', (tester) async {
      final documento = SeiDocumentoPendente.fromItens(
        id: 'doc-3',
        numeroDocumentoSei: '22222222',
        tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
        nomeArquivo: 'despacho3.pdf',
        hashSha256: 'hash3',
        versao: 1,
        criadoEm: DateTime(2026, 1, 1),
        criadoPorId: 'user-1',
        criadoPorNome: 'Fulano',
        itens: [
          _item(
            linha: 1,
            origemNome: 'Setor Sem Sigla Cadastrada',
            destinoNome: 'GETEC',
            destinoSigla: 'GETEC',
          ),
        ],
      );

      await _pumpDialogo(tester, documento);

      expect(find.text('Setor Sem Sigla Cadastrada'), findsOneWidget);
    });
  });

  group('a ficha da pendência guarda o que saiu da listagem', () {
    testWidgets('mostra tipo, processo, assunto, data de cadastro, contadores, autor e todos os itens', (tester) async {
      final documento = SeiDocumentoPendente.fromItens(
        id: '4006bdf4-6927-444e-912b-0e4d42653500',
        numeroDocumentoSei: '95955192',
        numeroProcesso: '202600017000011',
        numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
        assunto: 'Transferência de equipamentos de informática entre gerências',
        tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
        nomeArquivo: 'despacho.pdf',
        hashSha256: 'hash',
        versao: 1,
        criadoEm: DateTime(2026, 9, 22, 10, 5),
        criadoPorId: 'user-1',
        criadoPorNome: 'Fulano',
        itens: [
          _item(linha: 1, origemNome: 'Gerencia de Tecnologia', origemSigla: 'GETEC', destinoNome: 'GEASI', destinoSigla: 'GEASI'),
          _item(linha: 2, origemNome: 'Gerencia de Tecnologia', origemSigla: 'GETEC', destinoNome: 'GEASI', destinoSigla: 'GEASI'),
        ],
      );

      await _pumpDialogo(tester, documento);

      expect(find.text('577/2026/SEMAD/GETEC-12014'), findsOneWidget);
      expect(find.text('Tipo: Transferência'), findsOneWidget);
      expect(find.text('Processo: 202600017000011'), findsOneWidget);
      expect(find.text('Assunto: Transferência de equipamentos de informática entre gerências'), findsOneWidget);
      expect(find.text('Cadastrado em 22/09/2026 10:05'), findsOneWidget);
      expect(find.text('Cadastrado por Fulano'), findsOneWidget);
      expect(find.textContaining('2 item(ns) — 2 pendente(s), 0 concluído(s), 0 cancelado(s)'), findsOneWidget);
      // Todos os itens, com patrimônio e chamado.
      expect(find.text('1001'), findsOneWidget);
      expect(find.text('1002'), findsOneWidget);
      expect(find.text('4556'), findsNWidgets(2));
      expect(find.text('Histórico de alterações'), findsOneWidget);
    });

    testWidgets('sem assunto, a ficha não mostra a linha "Assunto"', (tester) async {
      final documento = SeiDocumentoPendente.fromItens(
        id: 'doc-1',
        numeroDocumentoSei: '1',
        tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
        nomeArquivo: 'despacho.pdf',
        hashSha256: 'hash',
        versao: 1,
        criadoEm: DateTime(2026, 1, 1),
        criadoPorId: 'user-1',
        criadoPorNome: 'Fulano',
        itens: [_item(linha: 1, origemNome: 'GETEC', destinoNome: 'GEASI')],
      );

      await _pumpDialogo(tester, documento);

      expect(find.textContaining('Assunto:'), findsNothing);
      expect(find.text('Cadastrado em 01/01/2026 00:00'), findsOneWidget);
    });
  });
}
