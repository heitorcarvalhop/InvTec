import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduz um erro técnico (Postgrest/GoTrue/rede/qualquer outro) numa
/// mensagem segura em PT-BR para exibir ao usuário. Usado pelo fluxo de
/// cadastro ([lib/features/auth/presentation/sign_up_controller.dart]) e
/// pelas telas administrativas (RPCs de `aprovar_usuario`,
/// `rejeitar_usuario`, `bloquear_usuario`, etc. — migration
/// `20261005130000_add_admin_user_rpcs.sql`) consumidas pelo agente
/// administracao-core.
///
/// Regra central: NUNCA deixa passar um erro cru/não reconhecido (SQLSTATE,
/// nome de constraint, stack trace) — só os casos abaixo, mapeados
/// manualmente, ou o fallback genérico.
///
/// Correspondência com as mensagens reais das RPCs administrativas (as 7
/// funções de `20261005130000_add_admin_user_rpcs.sql` e as 5 de
/// `20261006110000_add_has_permission_and_override_rpcs.sql`): todas elas
/// já lançam `raise exception 'mensagem em PT-BR amigável'` escrita pelos
/// autores da migration — ex. tentar remover o último ADMIN ativo devolve
/// literalmente "Não é possível remover o último administrador ativo do
/// sistema". Essas mensagens já são o que a UI deve mostrar, então esta
/// função as repassa DIRETAMENTE (via `PostgrestException.message`) sem
/// reescrevê-las — só garante que, se um dia uma RPC nova lançar algo cru
/// (ex. uma violação de FK não tratada), o fallback genérico entra no lugar
/// em vez de vazar SQLSTATE/nome de tabela.
String traduzirErroSupabase(Object error) {
  if (error is PostgrestException) {
    return _traduzirPostgrestException(error);
  }

  // AuthRetryableFetchException É uma AuthException (subtipo) — precisa
  // ser checada ANTES do `is AuthException` genérico abaixo, senão nunca
  // seria alcançada.
  if (error is AuthRetryableFetchException || error is SocketException) {
    return 'Não foi possível conectar. Verifique sua conexão e tente novamente.';
  }

  if (error is AuthException) {
    return _traduzirAuthException(error);
  }

  return _mensagemFallbackGenerica;
}

const _mensagemFallbackGenerica =
    'Não foi possível concluir a operação. Tente novamente em alguns instantes.';

const _mensagemCadastroDuplicado =
    'Não foi possível concluir o cadastro. Verifique se os dados informados já estão associados a uma conta.';

/// Códigos lançados pelas RPCs administrativas (ver cabeçalho desta
/// função): a mensagem já vem pronta em PT-BR em `error.message` — só
/// repassamos. `23505` (unique_violation) é tratado separadamente porque,
/// nesse caso específico, o Postgres não escreve uma frase amigável — por
/// isso a mensagem NEUTRA abaixo (nunca dá para saber com certeza, só pelo
/// código, se foi e-mail ou CPF duplicado).
const _codigosComMensagemAmigavelPronta = {'P0001', 'P0002', '42501', 'P0021'};

String _traduzirPostgrestException(PostgrestException error) {
  final codigo = error.code;
  if (codigo != null && _codigosComMensagemAmigavelPronta.contains(codigo)) {
    final mensagem = error.message.trim();
    // Rede de segurança: só repassa se não parecer um erro cru (nunca deixa
    // passar algo que pareça SQLSTATE/nome de constraint/stack trace).
    if (mensagem.isNotEmpty && !_pareceErroCru(mensagem)) {
      return mensagem;
    }
    return _mensagemFallbackGenerica;
  }

  if (codigo == '23505') {
    return _mensagemCadastroDuplicado;
  }

  return _mensagemFallbackGenerica;
}

String _traduzirAuthException(AuthException error) {
  final mensagem = error.message.toLowerCase();
  if (mensagem.contains('already registered') || mensagem.contains('already exists')) {
    return _mensagemCadastroDuplicado;
  }
  return _mensagemFallbackGenerica;
}

/// Heurística simples para nunca repassar algo que pareça um erro técnico
/// cru, mesmo vindo de um código "confiável" — defesa em profundidade, não
/// o mecanismo primário (o mecanismo primário é a migration SEMPRE escrever
/// mensagens amigáveis nos `raise exception`).
bool _pareceErroCru(String mensagem) {
  final padroesTecnicos = [
    RegExp(r'^[0-9A-Z]{5}$'), // SQLSTATE puro
    RegExp(r'relation ".*" does not exist'),
    RegExp(r'constraint ".*"'),
    RegExp(r'at character \d+'),
  ];
  return padroesTecnicos.any((p) => p.hasMatch(mensagem));
}
