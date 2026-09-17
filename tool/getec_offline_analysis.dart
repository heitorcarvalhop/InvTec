// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/getec_import_profile.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/import_profile_id.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

// ignore: depend_on_referenced_packages
import '../test/features/dashboard/fake_dashboard_repository.dart';
import '../test/features/patrimonios/fake_patrimonio_repository.dart';
import '../test/features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../test/features/setores/fake_setor_repository.dart';

/// Diagnóstico OFFLINE e manual com o arquivo real local (Prompt 8.7, seção
/// 35) — usa o `PatrimonioImportController` DE PRODUÇÃO, ponta a ponta, mas
/// com repositórios FAKE (em memória): nenhuma chamada de rede, nenhuma
/// escrita, nenhum contato com o Supabase real.
///
/// Fica em tool/ (fora de test/) de propósito: NÃO roda como parte de
/// `flutter test`. Para rodar:
///   flutter test tool/getec_offline_analysis.dart
///
/// Catálogo de tipos usado aqui é o catálogo OFICIAL descrito na migration
/// pendente (20260911130000_update_tipos_patrimonio_catalog.sql, ainda não
/// aplicada) — local, fabricado só para este diagnóstico, nunca gravado em
/// lugar nenhum.
final _tiposCatalogoOficial = [
  'Notebook',
  'Desktop',
  'Monitor',
  'Impressora',
  'Nobreak',
  'Servidor',
  'TV',
  'Projetor',
  'Equipamento de Rede',
  'Estabilizador',
  'Mobiliário',
  'Software / Licença',
  'Certificado Digital',
  'Outros',
].asMap().entries.map(
  (e) => TipoPatrimonio(id: 'tipo-${e.key}', nome: e.value, ativo: true, criadoEm: DateTime(2026, 1, 1)),
).toList();

void main() {
  test('diagnóstico offline — planilha real GETEC (sem Supabase, sem escrita)', () async {
    final arquivo = File('local_test_data/BENS DA GETEC.xlsx');
    expect(
      arquivo.existsSync(),
      isTrue,
      reason: 'Esperado em local_test_data/BENS DA GETEC.xlsx (fora do git).',
    );
    final bytes = await arquivo.readAsBytes();

    final container = ProviderContainer(
      overrides: [
        patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(tipos: _tiposCatalogoOficial),
        ),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: const [])),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(patrimonioImportControllerProvider, (_, _) {});
    final controller = container.read(patrimonioImportControllerProvider.notifier);

    print('\n================ 1. ARQUIVO ================');
    final cronometroParse = Stopwatch()..start();
    await controller.carregarArquivo(nomeArquivo: 'BENS DA GETEC.xlsx', bytes: bytes);
    cronometroParse.stop();

    var state = container.read(patrimonioImportControllerProvider);
    print('Tempo de leitura/parsing: ${cronometroParse.elapsedMilliseconds} ms');
    print('Abas encontradas: ${state.abas.map((a) => '"${a.nome}" (${a.linhas.length} linhas)').join(', ')}');

    if (state.step == ImportStep.selecionarAba) {
      final maior = state.abas.indexWhere(
        (a) => a.linhas.length == state.abas.map((x) => x.linhas.length).reduce((a, b) => a > b ? a : b),
      );
      controller.selecionarAba(maior);
      state = container.read(patrimonioImportControllerProvider);
      print('Múltiplas abas — usando a maior: "${state.abaSelecionada!.nome}"');
    }
    print('Aba usada: "${state.abaSelecionada!.nome}"');
    print('Linha de cabeçalho sugerida (índice): ${state.indiceCabecalho}');
    print('Cabeçalho: ${state.linhaCabecalho}');
    print('Total de linhas na aba (com cabeçalho): ${state.abaSelecionada!.linhas.length}');

    print('\n================ 2. PERFIL GETEC ================');
    controller.confirmarCabecalho();
    state = container.read(patrimonioImportControllerProvider);
    print('perfilDetectado: ${state.perfilDetectado}');
    final cabecalhoTexto = state.linhaCabecalho.map((c) => c?.toString() ?? '').toList();
    print('Cabeçalhos brutos lidos: $cabecalhoTexto');
    if (state.perfilDetectado != ImportProfileId.getecLegado) {
      fail('Perfil GETEC NÃO foi detectado para este arquivo — abortando o resto do diagnóstico.');
    }
    print('Reconhecido: presença de "tombamento" + "descrição" e >=4 das 6 colunas conhecidas.');

    controller.ativarPerfilGetec();
    state = container.read(patrimonioImportControllerProvider);

    print('\n================ 3. MAPEAMENTO ================');
    const esperado = {
      ImportColumnField.numeroPatrimonio: 'tombamento',
      ImportColumnField.tombamentoAnterior: 'tomb_anterior',
      ImportColumnField.descricao: 'descricao',
      ImportColumnField.setor: 'localizacao',
      ImportColumnField.marca: 'marca',
      ImportColumnField.numeroSerie: 'n. serie',
    };
    var mapeamentoDivergente = false;
    for (final entry in esperado.entries) {
      final coluna = state.mapeamento.colunaDe(entry.key);
      final textoColuna = coluna == null ? null : cabecalhoTexto[coluna];
      final ok = coluna != null;
      if (!ok) mapeamentoDivergente = true;
      print('${entry.key} (esperado "${entry.value}") -> coluna $coluna ("$textoColuna") ${ok ? 'OK' : 'FALTOU'}');
    }
    if (mapeamentoDivergente) {
      print('*** ATENÇÃO: mapeamento divergiu do esperado — ver acima. ***');
    }

    print('\n================ 4 + 5. ANÁLISE COMPLETA (offline) ================');
    controller.definirPadroes(const ImportDefaults());
    final cronometroAnalise = Stopwatch()..start();
    await controller.analisar();
    cronometroAnalise.stop();
    state = container.read(patrimonioImportControllerProvider);
    print('Tempo de análise (inclui inferência de tipo): ${cronometroAnalise.elapsedMilliseconds} ms');

    final linhas = state.linhas;
    print('Total de linhas úteis (não vazias): ${linhas.length}');

    final tombamentosPreenchidos = linhas.where((l) => l.numeroPatrimonio != null).length;
    final tombamentosVazios = linhas.length - tombamentosPreenchidos;
    final duplicados = linhas.where((l) => l.duplicadoNoArquivo).length;
    print('Tombamentos preenchidos: $tombamentosPreenchidos');
    print('Tombamentos vazios: $tombamentosVazios');
    print('Linhas com tombamento duplicado dentro do arquivo: $duplicados');

    final tombAnteriorReal = linhas.where((l) => l.celulas[ImportColumnField.tombamentoAnterior] != null).length;
    print('Tombamentos anteriores reais (após regra do "10"): $tombAnteriorReal');

    final seriaisReais = linhas.where((l) => l.numeroSerie != null).length;
    final serialContagem = <String, int>{};
    for (final l in linhas) {
      final s = l.numeroSerie;
      if (s != null) serialContagem.update(s, (v) => v + 1, ifAbsent: () => 1);
    }
    final seriaisRepetidos = serialContagem.values.where((v) => v > 1).length;
    print('Números de série reais (após regra do "10"): $seriaisReais');
    print('Números de série distintos repetidos dentro do arquivo: $seriaisRepetidos');
    print('Linhas com possível duplicidade de serial (flag): ${linhas.where((l) => l.possivelDuplicidadeSerial).length}');

    final colunaLocalizacao = state.mapeamento.colunaDe(ImportColumnField.setor)!;
    final localizacoes = GetecImportProfile.localizacoesUnicas(
      linhas: state.abaSelecionada!.linhas,
      indiceCabecalho: state.indiceCabecalho,
      colunaLocalizacao: colunaLocalizacao,
    );
    print('Localizações únicas encontradas: ${localizacoes.length}');

    print('\n================ 5. INFERÊNCIA DE TIPOS ================');
    final nomePorTipoId = {for (final t in _tiposCatalogoOficial) t.id: t.nome};
    final contagemTipo = <String, int>{};
    var naoIdentificados = 0;
    for (final l in linhas) {
      final id = l.tipoIdResolvido;
      if (id == null) {
        naoIdentificados++;
      } else {
        final nome = nomePorTipoId[id] ?? id;
        contagemTipo.update(nome, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    for (final nome in _tiposCatalogoOficial.map((t) => t.nome)) {
      print('$nome: ${contagemTipo[nome] ?? 0}');
    }
    print('Não identificado: $naoIdentificados');
    final percentualClassificado = linhas.isEmpty ? 0.0 : (linhas.length - naoIdentificados) / linhas.length * 100;
    print('Classificado automaticamente: ${percentualClassificado.toStringAsFixed(1)}%');

    print('\n================ 6. OUTROS E NÃO IDENTIFICADOS ================');
    final idOutros = _tiposCatalogoOficial.firstWhere((t) => t.nome == 'Outros').id;
    final descricoesOutros = linhas.where((l) => l.tipoIdResolvido == idOutros).map((l) => l.descricao).whereType<String>().toList();
    final descricoesNaoIdentificadas = linhas.where((l) => l.tipoIdResolvido == null).map((l) => l.descricao).whereType<String>().toList();
    _relatarDescricoes('Outros', descricoesOutros);
    _relatarDescricoes('Não identificado', descricoesNaoIdentificadas);
    _agruparPorPadraoConhecido(descricoesNaoIdentificadas);
    _tabelaCompletaNaoIdentificados(descricoesNaoIdentificadas);

    print('\n================ 7. VALIDAR REGRAS IMPORTANTES ================');
    const amostras = {
      'NOTEBOOK': 'Notebook',
      'MONITOR': 'Monitor',
      'DESKTOP': 'Desktop',
      'SWITCH': 'Equipamento de Rede',
      'ACCESS POINT': 'Equipamento de Rede',
      'MOUSE': 'Outros',
      'TECLADO': 'Outros',
      'DOCK STATION': 'Outros',
      'SCANNER': 'Outros',
      'TABLET': 'Outros',
      'LICEN': 'Software / Licença',
      'CERTIFICADO DIGITAL': 'Certificado Digital',
    };
    for (final entry in amostras.entries) {
      final achados = linhas.where((l) => (l.descricao ?? '').toUpperCase().contains(entry.key)).toList();
      if (achados.isEmpty) {
        print('${entry.key}: nenhum exemplo encontrado na planilha real');
        continue;
      }
      final amostra = achados.take(3);
      for (final l in amostra) {
        final nomeResolvido = nomePorTipoId[l.tipoIdResolvido] ?? '(não identificado)';
        final ok = nomeResolvido == entry.value;
        print('${entry.key} | "${l.descricao}" -> $nomeResolvido ${ok ? '' : '*** ESPERADO ${entry.value} ***'}');
      }
    }

    print('\n================ 8. PRECEDÊNCIA ================');
    _checarPrecedencia(linhas, nomePorTipoId, 'LICEN', ['NOTEBOOK', 'DESKTOP', 'MONITOR']);
    _checarPrecedencia(linhas, nomePorTipoId, 'MONITOR', ['SUPORTE']);
    _checarPrecedencia(linhas, nomePorTipoId, 'SOFTWARE', ['COMPUTADOR']);

    print('\n================ 9. LOCALIZAÇÕES ================');
    for (final loc in localizacoes.take(60)) {
      print('${loc.texto} — ${loc.contagem} linha(s) — pendente de mapeamento (sem lista real de setores offline)');
    }
    if (localizacoes.length > 60) print('... e mais ${localizacoes.length - 60} localizações únicas.');

    print('\n================ 10. BAIXAS ================');
    final baixas = linhas.where((l) => l.possivelBaixa).toList();
    print('Linhas com possível baixa: ${baixas.length}');
    final locBaixas = <String, int>{};
    for (final l in baixas) {
      final texto = l.setorTexto ?? '(vazio)';
      locBaixas.update(texto, (v) => v + 1, ifAbsent: () => 1);
    }
    locBaixas.forEach((loc, qtd) => print('  localização "$loc": $qtd linha(s)'));
    for (final l in baixas.take(5)) {
      print('  exemplo: patrimônio ${l.numeroPatrimonio} — "${l.descricao}"');
    }
    final baixaVirouErroSoPorIsso = baixas.where((l) => l.status == ImportRowStatus.erro && l.issues.length == 1).length;
    print('Confirma que só gera AVISO (nunca bloqueia sozinha): ${baixaVirouErroSoPorIsso == 0}');

    print('\n================ 11. DADOS PROBLEMÁTICOS ================');
    print('Sem tipo resolvido: ${linhas.where((l) => l.tipoIdResolvido == null).length}');
    print('Sem localização informada: ${linhas.where((l) => l.setorTexto == null).length}');
    print('Com localização informada mas não resolvida (sem setor real/padrão): ${linhas.where((l) => l.setorTexto != null && l.destinoIdResolvido == null).length}');
    print('Sem marca: ${linhas.where((l) => l.marca == null).length}');
    print('Sem serial: ${linhas.where((l) => l.numeroSerie == null).length}');
    print('Com serial repetido no arquivo: ${linhas.where((l) => l.possivelDuplicidadeSerial).length}');
    print('Com possível baixa: ${baixas.length}');
    print('Com tombamento anterior: $tombAnteriorReal');

    print('\n================ 12. SIMULAÇÃO DO PREVIEW ================');
    final porStatus = <ImportRowStatus, int>{};
    for (final l in linhas) {
      porStatus.update(l.status, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final status in ImportRowStatus.values) {
      print('${status.name.toUpperCase()}: ${porStatus[status] ?? 0}');
    }
    print('(EXISTENTE/ATUALIZAR = 0 é esperado: repositório fake está vazio, sem correspondência com o banco real.)');

    final causasErro = <String, int>{};
    for (final l in linhas.where((l) => l.status == ImportRowStatus.erro)) {
      for (final issue in l.issues) {
        final chave = issue.message.split(':').first.split('.').first;
        causasErro.update(chave, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    print('Causas de ERRO (uma linha pode ter mais de uma):');
    final causasOrdenadas = causasErro.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final c in causasOrdenadas) {
      print('  ${c.key}: ${c.value}');
    }
    print('*** ERRO está inflado propositalmente: sem lista real de setores e sem padrão de origem/destino configurado, quase toda linha falha em origem/destino. Isso não reflete a planilha em si. ***');

    print('\n================ 13. PERFORMANCE ================');
    print('Parsing do arquivo: ${cronometroParse.elapsedMilliseconds} ms');
    print('Análise completa (inclui inferência de tipo por descrição em todas as linhas): ${cronometroAnalise.elapsedMilliseconds} ms');

    print('\n================ 14. MIGRATION DE TIPOS ================');
    print('Catálogo usado neste diagnóstico (idêntico ao da migration pendente, 14 tipos): ${_tiposCatalogoOficial.map((t) => t.nome).join(', ')}');
    print('Migration NÃO foi aplicada.');

    print('\n================ 15. SEGURANÇA ================');
    print('patrimonioRepositoryProvider usa FakePatrimonioRepository (memória) — nenhuma chamada de rede.');
    print('setorRepositoryProvider / tipoPatrimonioRepositoryProvider também fake.');
    print('Nenhum cadastrar()/atualizar() foi chamado neste diagnóstico.');

    print('\n================ FIM DO DIAGNÓSTICO ================');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

void _relatarDescricoes(String categoria, List<String> descricoes) {
  print('-- $categoria: ${descricoes.length} linha(s) --');
  final contagemExata = <String, int>{};
  for (final d in descricoes) {
    contagemExata.update(d, (v) => v + 1, ifAbsent: () => 1);
  }
  final top = contagemExata.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  print('  Descrições mais frequentes:');
  for (final e in top.take(10)) {
    print('    "${e.key}": ${e.value}');
  }

  const stopwords = {
    'de', 'da', 'do', 'das', 'dos', 'para', 'com', 'sem', 'e', 'a', 'o', 'em', 'no', 'na',
    'nos', 'nas', 'um', 'uma', 'ao', 'aos', 'por',
  };
  final contagemPalavra = <String, int>{};
  for (final d in descricoes) {
    for (final palavra in d.toLowerCase().split(RegExp(r'[^a-zà-ú0-9]+'))) {
      if (palavra.length < 3 || stopwords.contains(palavra)) continue;
      contagemPalavra.update(palavra, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final topPalavras = contagemPalavra.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  print('  Palavras/padrões mais recorrentes:');
  for (final e in topPalavras.take(15)) {
    print('    "${e.key}": ${e.value}');
  }
}

/// Relatório explícito pedido na rodada 2 (item 12): agrupa os "Não
/// identificado" restantes pelos padrões-chave já observados na planilha
/// real (RACK/GARANTIA/MULTÍMETRO/ESCADA), mais qualquer outro padrão de
/// palavra com 2+ ocorrências — sem sugerir nenhuma regra nova aqui, só
/// dados para decisão manual posterior.
void _agruparPorPadraoConhecido(List<String> descricoes) {
  print('-- Não identificado: agrupamento por padrão conhecido --');
  const watchlist = ['RACK', 'GARANTIA', 'MULTÍMETRO', 'MULTIMETRO', 'ESCADA'];
  for (final termo in watchlist) {
    // Palavra inteira, não substring — evita falso positivo tipo
    // "TRACKPAD" contendo "RACK".
    final achados = descricoes.where((d) => _contemPalavraInteira(d.toUpperCase(), termo)).toList();
    if (achados.isEmpty) continue;
    print('  "$termo": ${achados.length} linha(s)');
    for (final d in achados.take(10)) {
      print('    - "$d"');
    }
  }

  final cobertas = descricoes.where((d) => watchlist.any((t) => _contemPalavraInteira(d.toUpperCase(), t))).toSet();
  final restantes = descricoes.where((d) => !cobertas.contains(d)).toList();
  print('  Demais "Não identificado" (${restantes.length} linha(s), fora da watchlist acima) —'
      ' ver tabela completa logo abaixo.');
}

bool _contemPalavraInteira(String texto, String palavra) {
  var inicio = 0;
  while (true) {
    final indice = texto.indexOf(palavra, inicio);
    if (indice == -1) return false;
    final antes = indice == 0 ? null : texto[indice - 1];
    final fimIndice = indice + palavra.length;
    final depois = fimIndice >= texto.length ? null : texto[fimIndice];
    final ehLetra = RegExp(r'[A-ZÀ-Ú0-9]');
    final antesOk = antes == null || !ehLetra.hasMatch(antes);
    final depoisOk = depois == null || !ehLetra.hasMatch(depois);
    if (antesOk && depoisOk) return true;
    inicio = indice + 1;
  }
}

/// Tabela completa pedida na rodada 3 (seção 11): TODOS os "Não
/// identificado" agrupados por descrição exata, com contagem e uma coluna
/// de "tipo possível" — sugestão textual só para leitura humana, nunca
/// aplicada automaticamente.
void _tabelaCompletaNaoIdentificados(List<String> descricoes) {
  print('\n-- Tabela completa: Não identificado (agrupado por descrição) --');
  final contagem = <String, int>{};
  for (final d in descricoes) {
    contagem.update(d, (v) => v + 1, ifAbsent: () => 1);
  }
  final ordenado = contagem.entries.toList()
    ..sort((a, b) {
      final porContagem = b.value.compareTo(a.value);
      return porContagem != 0 ? porContagem : a.key.compareTo(b.key);
    });

  for (final entry in ordenado) {
    print('  [${entry.value}x] "${entry.key}" -> possível: ${_sugestaoTextual(entry.key)}');
  }
}

/// Só texto para leitura humana (seção 11 desta rodada) — NUNCA usado para
/// resolver `tipoIdResolvido`, nunca lido por nenhum código de produção.
String _sugestaoTextual(String descricao) {
  final d = descricao.toUpperCase();
  if (_contemPalavraInteira(d, 'RACK')) return 'Equipamento de Rede / Outros (decisão pendente)';
  if (d.contains('GARANTIA')) return 'Outros / Ignorar (não é um bem físico)';
  if (d.contains('MULTÍMETRO') || d.contains('MULTIMETRO')) return 'Outros (fora do catálogo atual)';
  if (d.contains('ESCADA')) return 'Mobiliário / Outros (fora do catálogo atual)';
  if (d.contains('BATERIA')) return 'Outros / Nobreak (acessório)';
  if (d.contains('KEYBOARD')) return 'Outros (variante em inglês de "teclado")';
  if (d.contains('TELEVIISOR') || d.contains('TELEVISOR')) return 'TV (possível erro de digitação na planilha)';
  return 'Revisão manual';
}

void _checarPrecedencia(
  List<ImportRow> linhas,
  Map<String, String> nomePorTipoId,
  String chavePrincipal,
  List<String> chavesSecundarias,
) {
  for (final chaveSecundaria in chavesSecundarias) {
    final achados = linhas.where(
      (l) {
        final d = (l.descricao ?? '').toUpperCase();
        return d.contains(chavePrincipal) && d.contains(chaveSecundaria);
      },
    ).toList();
    if (achados.isEmpty) {
      print('$chavePrincipal + $chaveSecundaria: nenhum caso encontrado na planilha real');
      continue;
    }
    for (final l in achados.take(5)) {
      final nomeResolvido = nomePorTipoId[l.tipoIdResolvido] ?? '(não identificado)';
      print('$chavePrincipal + $chaveSecundaria | "${l.descricao}" -> $nomeResolvido');
    }
  }
}
