/// Modo de visualização de uma listagem paginada do InvTec — compartilhado
/// por Patrimônios e Movimentações, para nunca ter dois vocabulários
/// diferentes para o mesmo conceito. Persistido localmente por tela (cada
/// uma com sua própria chave de `SharedPreferences`), nunca no Supabase.
enum ListViewMode { list, cards }
