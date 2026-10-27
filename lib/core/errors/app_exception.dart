/// Erro de aplicação lançado pela camada de acesso a dados, envolvendo a
/// causa original (ex.: PostgrestException do Supabase) para não vazar
/// detalhes de infraestrutura até a camada de apresentação.
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException: $message';
}

/// Subtipo de [AppException] para quando o próprio Postgres recusou a
/// consulta por falta de permissão (`42501`/`insufficient_privilege`) —
/// distinto de uma falha de rede/transporte genérica, que um "tentar de
/// novo" pode resolver. Quem chama (ex.: o leitor de câmera de patrimônio)
/// usa este tipo para NUNCA confundir "não consegui confirmar se existe,
/// falta permissão" com "não encontrado" ou com "falha passageira" — as
/// três têm consequências de UI diferentes (nunca oferecer cadastro em
/// nenhuma das duas primeiras, por exemplo).
class AcessoInsuficienteException extends AppException {
  const AcessoInsuficienteException(super.message, {super.cause});
}
