/// Qual conjunto de regras de reconhecimento/pré-processamento está ativo
/// para a importação atual (seção 26). O importador genérico continua
/// funcionando de forma idêntica quando [generico] está ativo — nenhuma
/// regra específica de um perfil (ex.: GETEC) roda nesse caso.
enum ImportProfileId { generico, getecLegado }
