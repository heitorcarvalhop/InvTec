import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/administracao/domain/usuario_admin_repository.dart';
import 'package:invtec/features/auth/domain/profile.dart';

/// Fake em memória de [UsuarioAdminRepository] — sem Supabase real.
///
/// Reproduz as MESMAS regras das RPCs reais (ver
/// `supabase/migrations/20261005130000_add_admin_user_rpcs.sql`) o
/// suficiente para os controllers desta feature serem testados sem banco:
/// 3ª rejeição bloqueia automaticamente, desbloqueio decide ACTIVE/PENDING
/// conforme `approvedAt`, e a última linha de defesa do último ADMIN ACTIVE
/// (ver migration 20261005120000, seção 8) é simulada em
/// [_recusarSeUltimoAdminAtivo] — lança a MESMA `AppException` amigável que
/// o erro real do Postgres produziria depois de traduzido por
/// `traduzirErroSupabase`.
class FakeUsuarioAdminRepository implements UsuarioAdminRepository {
  FakeUsuarioAdminRepository({List<Profile> usuarios = const []})
    : _usuarios = List.of(usuarios);

  List<Profile> _usuarios;

  int aprovarCallCount = 0;
  int rejeitarCallCount = 0;
  int bloquearCallCount = 0;
  int desbloquearCallCount = 0;
  int alterarIdentidadeCallCount = 0;
  int alterarPerfilCallCount = 0;

  List<Profile> get usuariosParaTeste => List.unmodifiable(_usuarios);

  @override
  Future<List<Profile>> listar({
    required ProfileAccessStatus status,
    String? busca,
  }) async {
    var resultado = _usuarios.where((u) => u.accessStatus == status).toList();

    final termo = busca?.trim().toLowerCase();
    if (termo != null && termo.isNotEmpty) {
      final apenasDigitos = termo.replaceAll(RegExp(r'[^0-9]'), '');
      resultado = resultado.where((u) {
        final bateNome = u.nome.toLowerCase().contains(termo);
        final bateEmail = (u.email ?? '').toLowerCase().contains(termo);
        final bateCpf = apenasDigitos.isNotEmpty && (u.cpf ?? '').contains(apenasDigitos);
        return bateNome || bateEmail || bateCpf;
      }).toList();
    }

    return resultado;
  }

  @override
  Future<Profile> buscarPorId(String userId) async => _encontrar(userId);

  Profile _encontrar(String userId) {
    return _usuarios.firstWhere(
      (u) => u.id == userId,
      orElse: () => throw const AppException('Usuário não encontrado.'),
    );
  }

  void _substituir(Profile atualizado) {
    _usuarios = [for (final u in _usuarios) if (u.id == atualizado.id) atualizado else u];
  }

  Profile _comCampos(
    Profile base, {
    String? nome,
    String? cpf,
    bool? manterCpf,
    ProfilePerfil? perfil,
    bool? ativo,
    ProfileAccessStatus? accessStatus,
    int? rejectionCount,
    DateTime? approvedAt,
    String? approvedBy,
    Object? rejectedReason = _semAlteracao,
    Object? blockedReason = _semAlteracao,
  }) {
    return Profile(
      id: base.id,
      nome: nome ?? base.nome,
      email: base.email,
      cpf: manterCpf == true ? base.cpf : (cpf ?? base.cpf),
      perfil: perfil ?? base.perfil,
      ativo: ativo ?? base.ativo,
      accessStatus: accessStatus ?? base.accessStatus,
      rejectionCount: rejectionCount ?? base.rejectionCount,
      approvedAt: approvedAt ?? base.approvedAt,
      approvedBy: approvedBy ?? base.approvedBy,
      rejectedReason: rejectedReason == _semAlteracao ? base.rejectedReason : rejectedReason as String?,
      blockedReason: blockedReason == _semAlteracao ? base.blockedReason : blockedReason as String?,
      criadoEm: base.criadoEm,
      atualizadoEm: DateTime(2026, 1, 2),
    );
  }

  /// Simula a trigger real `trg_profiles_prevent_remove_last_active_admin`
  /// (migration 20261005120000, seção 8): tirar o ÚLTIMO ADMIN ACTIVE dessa
  /// condição é sempre recusado.
  void _recusarSeUltimoAdminAtivo(
    Profile antes, {
    ProfilePerfil? novoPerfil,
    ProfileAccessStatus? novoStatus,
  }) {
    final eraAdminAtivo = antes.perfil == ProfilePerfil.admin && antes.accessStatus == ProfileAccessStatus.active;
    final continuaAdminAtivo =
        (novoPerfil ?? antes.perfil) == ProfilePerfil.admin &&
        (novoStatus ?? antes.accessStatus) == ProfileAccessStatus.active;

    if (eraAdminAtivo && !continuaAdminAtivo) {
      final outrosAdminsAtivos = _usuarios.where(
        (u) => u.id != antes.id && u.perfil == ProfilePerfil.admin && u.accessStatus == ProfileAccessStatus.active,
      ).length;
      if (outrosAdminsAtivos == 0) {
        throw const AppException('Não é possível remover o último administrador ativo do sistema.');
      }
    }
  }

  @override
  Future<Profile> aprovar({required String userId, required ProfilePerfil perfil}) async {
    aprovarCallCount++;
    final antes = _encontrar(userId);
    if (antes.accessStatus != ProfileAccessStatus.pending) {
      throw const AppException('Usuário não está com solicitação pendente.');
    }
    final depois = _comCampos(
      antes,
      perfil: perfil,
      ativo: true,
      accessStatus: ProfileAccessStatus.active,
      approvedAt: DateTime(2026, 1, 2),
      approvedBy: 'fake-admin-id',
      rejectedReason: null,
      blockedReason: null,
    );
    _substituir(depois);
    return depois;
  }

  @override
  Future<Profile> rejeitar({required String userId, required String motivo}) async {
    rejeitarCallCount++;
    final antes = _encontrar(userId);
    if (antes.accessStatus != ProfileAccessStatus.pending) {
      throw const AppException('Usuário não está com solicitação pendente.');
    }
    final novoCount = antes.rejectionCount + 1;
    final bloqueado = novoCount >= 3;
    final depois = _comCampos(
      antes,
      ativo: false,
      accessStatus: bloqueado ? ProfileAccessStatus.blocked : ProfileAccessStatus.rejected,
      rejectionCount: novoCount,
      rejectedReason: motivo,
      blockedReason: bloqueado ? motivo : antes.blockedReason,
    );
    _substituir(depois);
    return depois;
  }

  @override
  Future<Profile> bloquear({required String userId, required String motivo}) async {
    bloquearCallCount++;
    final antes = _encontrar(userId);
    if (antes.accessStatus == ProfileAccessStatus.blocked) {
      throw const AppException('Usuário já está bloqueado.');
    }
    _recusarSeUltimoAdminAtivo(antes, novoStatus: ProfileAccessStatus.blocked);
    final depois = _comCampos(
      antes,
      ativo: false,
      accessStatus: ProfileAccessStatus.blocked,
      blockedReason: motivo,
    );
    _substituir(depois);
    return depois;
  }

  @override
  Future<Profile> desbloquear(String userId) async {
    desbloquearCallCount++;
    final antes = _encontrar(userId);
    if (antes.accessStatus != ProfileAccessStatus.blocked) {
      throw const AppException('Usuário não está bloqueado.');
    }

    final Profile depois;
    if (antes.approvedAt != null) {
      depois = _comCampos(antes, ativo: true, accessStatus: ProfileAccessStatus.active, blockedReason: null);
    } else {
      depois = _comCampos(
        antes,
        ativo: false,
        accessStatus: ProfileAccessStatus.pending,
        rejectionCount: 0,
        rejectedReason: null,
        blockedReason: null,
      );
    }
    _substituir(depois);
    return depois;
  }

  @override
  Future<Profile> alterarIdentidade({
    required String userId,
    required String nome,
    required String cpf,
    required String motivo,
  }) async {
    alterarIdentidadeCallCount++;
    final antes = _encontrar(userId);
    final depois = _comCampos(antes, nome: nome, cpf: cpf);
    _substituir(depois);
    return depois;
  }

  @override
  Future<Profile> alterarPerfil({required String userId, required ProfilePerfil perfil}) async {
    alterarPerfilCallCount++;
    final antes = _encontrar(userId);
    _recusarSeUltimoAdminAtivo(antes, novoPerfil: perfil);
    final depois = _comCampos(antes, perfil: perfil);
    _substituir(depois);
    return depois;
  }
}

/// Sentinela interna de [FakeUsuarioAdminRepository._comCampos] — distingue
/// "parâmetro omitido" (mantém o valor atual) de "null explícito" (limpa o
/// campo), já que `rejectedReason`/`blockedReason` são, eles mesmos,
/// `String?`.
const Object _semAlteracao = Object();
