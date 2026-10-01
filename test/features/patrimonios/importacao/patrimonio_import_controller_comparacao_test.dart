import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/domain/patrimonio_comparacao.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// PROMPT 11.6.2 — testes do modo ADMIN "Comparar e Atualizar"
/// (`PatrimonioImportController.compararParaAdmin`). Reaproveita
/// DELIBERADAMENTE o mesmo formato de fixtures/helpers de
/// `patrimonio_import_controller_test.dart` (tipos/setores/localizações),
/// sem importar nada de lá (privado àquele arquivo) — mesmo padrão de
/// dados, arquivo de teste independente.
final _tipos = [
  TipoPatrimonio(id: 'tipo-notebook', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-gesia', nome: 'GESIA', sigla: 'GESIA', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
final _localizacoes = [
  Localizacao(
    id: 'loc-universitario',
    setorId: 'setor-getec',
    nome: 'GETEC - Universitário',
    ativo: true,
    criadoEm: DateTime(2026, 1, 1),
  ),
  // Nome EXATO da lista oficial de `GetecImportProfile` (sem espaços em
  // volta do hífen) — "GETEC - PPLT" (com espaços) NÃO normaliza igual a
  // "GETEC-PPLT": `normalizarTextoComparacao` só remove acentos/caixa e
  // colapsa espaços, nunca mexe em pontuação.
  Localizacao(
    id: 'loc-pplt',
    setorId: 'setor-getec',
    nome: 'GETEC-PPLT',
    ativo: true,
    criadoEm: DateTime(2026, 1, 1),
  ),
];

Profile _perfil(ProfilePerfil perfil) => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@invtec.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
);

Uint8List _csv(String conteudo) => Uint8List.fromList(utf8.encode(conteudo));

ProviderContainer _criarContainer({required FakePatrimonioRepository repositorio, required ProfilePerfil perfil}) {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(perfil));
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
      localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: _localizacoes)),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
      authRepositoryProvider.overrideWithValue(auth),
    ],
  );
  container.listen(patrimonioImportControllerProvider, (_, _) {});
  addTearDownContainer(container, auth);
  return container;
}

/// `addTearDown` só está disponível dentro de um `test()`/`setUp` — como
/// este helper é chamado de dentro dos testes, isto é só um repasse com
/// nome mais claro (evita esquecer de descartar o [FakeAuthRepository]).
void addTearDownContainer(ProviderContainer container, FakeAuthRepository auth) {
  addTearDown(() {
    container.dispose();
    auth.dispose();
  });
}

const _cabecalhoGetec = 'tombamento;descricao;localizacao;marca;n. serie';

final _padroesGetec = ImportDefaults(destinoPadraoId: 'setor-getec', dataPadrao: DateTime(2026, 1, 1));

void main() {
  group('compararParaAdmin — restrição de perfil (seção 6)', () {
    test('perfil não-ADMIN: recusado, nada é lido nem analisado', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.gestor);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      // aguarda a sessão resolver antes de testar o gate.
      await container.read(authControllerProvider.future);

      const csv = '$_cabecalhoGetec\n123456;Notebook Dell;GETEC - Universitário;DELL;SN1\n';
      await controller.carregarArquivo(nomeArquivo: 'planilha.csv', bytes: _csv(csv));
      controller.confirmarCabecalho();
      controller.ativarPerfilGetec();
      controller.definirPadroes(_padroesGetec);

      await controller.compararParaAdmin();

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.mensagemErro, mensagemComparacaoRestritaAdmin);
      expect(state.comparacao, isNull);
      // nem chegou a rodar `analisar()`: nenhuma consulta em lote foi feita.
      expect(repo.buscarPorNumerosPatrimonioCallCount, 0);
      expect(repo.cadastrarCallCount, 0);
      expect(repo.atualizarCallCount, 0);
    });

    test('perfil ADMIN: autorizado a comparar', () async {
      final banco = _existente();
      final repo = FakePatrimonioRepository(itens: [banco]);
      final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      await container.read(authControllerProvider.future);

      const csv = '$_cabecalhoGetec\n123456;Notebook Dell;GETEC - Universitário;DELL;SN1\n';
      await controller.carregarArquivo(nomeArquivo: 'planilha.csv', bytes: _csv(csv));
      controller.confirmarCabecalho();
      controller.ativarPerfilGetec();
      controller.definirPadroes(_padroesGetec);

      await controller.compararParaAdmin();

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.mensagemErro, isNull);
      expect(state.comparacao, isNotNull);
    });
  });

  group('compararParaAdmin — exemplo do PROMPT 11.6.2 (seção 4)', () {
    test(
      'Patrimônio 123456: Localização diverge (GETEC-PPLT vs GETEC - Universitário), Marca idêntica (DELL)',
      () async {
        // Banco: Localização = GETEC - Universitário · Marca = DELL.
        final banco = _existente(localizacaoAtualId: 'loc-universitario', marca: 'DELL', numeroSerie: 'SN1');
        final repo = FakePatrimonioRepository(itens: [banco]);
        final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
        final controller = container.read(patrimonioImportControllerProvider.notifier);
        await container.read(authControllerProvider.future);

        // Planilha: Localização = GETEC-PPLT · Marca = DELL (idêntica) ·
        // mesma série (só a localização deve divergir, como no exemplo do
        // PROMPT 11.6.2). "GETEC-PPLT" é um dos 15 nomes oficiais
        // conhecidos da GETEC — resolve sozinho contra a `Localizacao`
        // cadastrada, sem precisar de mapeamento manual.
        const csv = '$_cabecalhoGetec\n123456;Notebook Dell;GETEC-PPLT;DELL;SN1\n';
        await controller.carregarArquivo(nomeArquivo: 'planilha.csv', bytes: _csv(csv));
        controller.confirmarCabecalho();
        controller.ativarPerfilGetec();
        controller.definirPadroes(_padroesGetec);

        await controller.compararParaAdmin();

        final comparacao = container.read(patrimonioImportControllerProvider).comparacao!;
        final item = comparacao.itens.single;

        expect(item.classificacao, ClassificacaoComparacao.divergente);
        // "1 divergência de localização. Marca idêntica, sem necessidade de revisão."
        expect(item.divergencias, hasLength(1));
        expect(item.divergencias.single.tipo, TipoDivergencia.localizacao);
        expect(item.divergencias.single.valorInvtec, 'GETEC - Universitário');
        expect(item.divergencias.single.valorPlanilha, 'GETEC-PPLT');
        expect(comparacao.resumo.divergentes, 1);
        expect(comparacao.resumo.identicos, 0);
      },
    );
  });

  group('compararParaAdmin — nenhuma escrita (seção 6/9)', () {
    test('mesmo com divergências e novos na planilha, cadastrar()/atualizar() nunca são chamados', () async {
      final banco = _existente();
      final repo = FakePatrimonioRepository(itens: [banco]);
      final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      await container.read(authControllerProvider.future);

      const csv =
          '$_cabecalhoGetec\n'
          '123456;Notebook Dell DIFERENTE;GETEC - Universitário;LENOVO;SN1\n' // existente, divergente
          '999999;NOTEBOOK LENOVO NOVO;GETEC - Universitário;LG;SN2\n'; // novo (descrição inferível — a GETEC não mapeia coluna de tipo)
      await controller.carregarArquivo(nomeArquivo: 'planilha.csv', bytes: _csv(csv));
      controller.confirmarCabecalho();
      controller.ativarPerfilGetec();
      controller.definirPadroes(_padroesGetec);

      await controller.compararParaAdmin();

      final comparacao = container.read(patrimonioImportControllerProvider).comparacao!;
      expect(comparacao.resumo.divergentes, 1);
      expect(comparacao.resumo.novos, 1);
      // o ponto central da seção 6: só CONSULTA e COMPARA.
      expect(repo.cadastrarCallCount, 0);
      expect(repo.atualizarCallCount, 0);
      // consultou o banco (buscarPorNumerosPatrimonio), nunca escreveu.
      expect(repo.buscarPorNumerosPatrimonioCallCount, greaterThan(0));
    });
  });

  group('compararParaAdmin — planilha com ~500 patrimônios (seção 7.8, ponta a ponta)', () {
    test('500 linhas via pipeline real (CSV → mapeamento → analisar → comparar) sem exceções nem escrita', () async {
      final linhasCsv = StringBuffer('$_cabecalhoGetec\n');
      final itensBanco = <PatrimonioDetalhe>[];
      for (var i = 0; i < 500; i++) {
        final numero = '${500000 + i}';
        // metade já existe no banco (idêntica), metade é nova.
        if (i.isEven) {
          itensBanco.add(
            _existente(
              id: 'p-$i',
              numeroPatrimonio: numero,
              descricao: 'Item $i',
              marca: 'DELL',
              numeroSerie: 'SN$i',
              localizacaoAtualId: 'loc-universitario',
            ),
          );
          linhasCsv.writeln('$numero;Item $i;GETEC - Universitário;DELL;SN$i');
        } else {
          // descrição inferível ("NOTEBOOK") — a GETEC não mapeia coluna de
          // tipo; sem isso, a linha ficaria bloqueada por "tipo obrigatório",
          // nunca classificada como NOVO.
          linhasCsv.writeln('$numero;NOTEBOOK LENOVO $i;GETEC - Universitário;LG;SN$i');
        }
      }

      final repo = FakePatrimonioRepository(itens: itensBanco);
      final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      await container.read(authControllerProvider.future);

      await controller.carregarArquivo(nomeArquivo: 'planilha_500.csv', bytes: _csv(linhasCsv.toString()));
      controller.confirmarCabecalho();
      controller.ativarPerfilGetec();
      controller.definirPadroes(_padroesGetec);

      await controller.compararParaAdmin();

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.mensagemErro, isNull);
      final comparacao = state.comparacao!;
      expect(comparacao.resumo.totalLinhas, 500);
      expect(comparacao.resumo.identicos, 250);
      expect(comparacao.resumo.novos, 250);
      expect(comparacao.resumo.identicos + comparacao.resumo.divergentes + comparacao.resumo.novos + comparacao.resumo.bloqueados, 500);
      expect(repo.cadastrarCallCount, 0);
      expect(repo.atualizarCallCount, 0);
      // uma única consulta em lote (nunca 500 chamadas individuais).
      expect(repo.buscarPorNumerosPatrimonioCallCount, 1);
    });
  });

  group('compararParaAdmin — importação convencional preservada (seção 10)', () {
    test(
      'sem nunca chamar compararParaAdmin, analisar()/confirmarImportacao() continuam com o comportamento de sempre',
      () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.operador);
        final controller = container.read(patrimonioImportControllerProvider.notifier);
        await container.read(authControllerProvider.future);

        const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n00045872;Notebook;Dell;AAA1;GETEC\n';
        await controller.carregarArquivo(nomeArquivo: 'inventario.csv', bytes: _csv(csv));
        controller.confirmarCabecalho();
        controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
        controller.definirColuna(ImportColumnField.tipo, 1);
        controller.definirColuna(ImportColumnField.marca, 2);
        controller.definirColuna(ImportColumnField.numeroSerie, 3);
        controller.definirColuna(ImportColumnField.setor, 4);
        controller.avancarParaPadroes();
        controller.definirPadroes(const ImportDefaults(origemPadraoId: 'setor-gesia'));
        await controller.analisar();

        final state = container.read(patrimonioImportControllerProvider);
        expect(state.step, ImportStep.revisar);
        expect(state.linhas.single.status, ImportRowStatus.pronto);
        // `comparacao` nunca é tocado pelo caminho convencional.
        expect(state.comparacao, isNull);

        await controller.confirmarImportacao();
        expect(repo.cadastrarCallCount, 1);
        expect(repo.atualizarCallCount, 0);
      },
    );
  });
}

PatrimonioDetalhe _existente({
  String id = 'p-123456',
  String numeroPatrimonio = '123456',
  String? descricao = 'Notebook Dell',
  String? marca = 'DELL',
  String? numeroSerie,
  String setorAtualId = 'setor-getec',
  String setorNome = 'GETEC',
  String? localizacaoAtualId,
}) {
  final localizacaoNome = localizacaoAtualId == null
      ? null
      : _localizacoes.firstWhere((l) => l.id == localizacaoAtualId).nome;
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numeroPatrimonio,
      tipoId: 'tipo-notebook',
      descricao: descricao,
      marca: marca,
      numeroSerie: numeroSerie,
      status: PatrimonioStatus.emUso,
      setorAtualId: setorAtualId,
      localizacaoAtualId: localizacaoAtualId,
      responsavelAtual: 'João',
      dataCadastro: DateTime(2024, 1, 1),
      atualizadoEm: DateTime(2024, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: setorNome,
    localizacaoNome: localizacaoNome,
  );
}
