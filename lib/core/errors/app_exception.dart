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
