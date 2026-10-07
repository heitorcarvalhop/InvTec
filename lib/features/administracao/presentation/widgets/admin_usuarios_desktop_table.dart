import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/domain/profile.dart';
import 'admin_usuario_formatters.dart';
import 'admin_usuario_status_chip.dart';

/// Mesma altura mínima de linha usada em `SetorDesktopTable` — densidade
/// consistente entre as listagens administrativas do app.
const double _alturaMinimaLinha = 56;
const double _larguraColunaAcoes = 56;

/// Lista estruturada (não `DataTable`) — cada célula usa `Expanded` próprio,
/// nunca sofre overflow horizontal em janelas estreitas (mesmo padrão de
/// `SetorDesktopTable`/`PatrimonioDesktopTable`).
class AdminUsuariosDesktopTable extends StatelessWidget {
  const AdminUsuariosDesktopTable({
    super.key,
    required this.usuarios,
    required this.onVerDetalhes,
  });

  final List<Profile> usuarios;
  final ValueChanged<Profile> onVerDetalhes;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _HeaderRow(),
          const Divider(height: 1),
          for (var i = 0; i < usuarios.length; i++) ...[
            _DataRow(usuario: usuarios[i], onVerDetalhes: () => onVerDetalhes(usuarios[i])),
            if (i < usuarios.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.label(context);
    return Container(
      color: Theme.of(context).surfaceColors.tableHeader,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Nome', style: style)),
          Expanded(flex: 3, child: Text('E-mail', style: style)),
          Expanded(flex: 2, child: Text('CPF', style: style)),
          Expanded(flex: 2, child: Text('Perfil', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          Expanded(flex: 1, child: Text('Rejeições', style: style)),
          Expanded(flex: 2, child: Text('Cadastro', style: style)),
          SizedBox(width: _larguraColunaAcoes, child: Text('', style: style)),
        ],
      ),
    );
  }
}

class _DataRow extends StatefulWidget {
  const _DataRow({required this.usuario, required this.onVerDetalhes});

  final Profile usuario;
  final VoidCallback onVerDetalhes;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final usuario = widget.usuario;
    final cpfMascarado = formatarCpfMascarado(usuario.cpf);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onVerDetalhes,
        child: Container(
          color: _hovering ? Theme.of(context).surfaceColors.rowHover : null,
          constraints: const BoxConstraints(minHeight: _alturaMinimaLinha),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 3, child: Text(usuario.nome, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 3, child: Text(usuario.email ?? '—', overflow: TextOverflow.ellipsis)),
              Expanded(
                flex: 2,
                child: Text(cpfMascarado ?? 'Não informado', overflow: TextOverflow.ellipsis),
              ),
              Expanded(flex: 2, child: Text(usuario.perfil.label, overflow: TextOverflow.ellipsis)),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AdminUsuarioStatusChip(status: usuario.accessStatus),
                ),
              ),
              Expanded(flex: 1, child: Text('${usuario.rejectionCount}')),
              Expanded(flex: 2, child: Text(formatarDataCurta(usuario.criadoEm))),
              SizedBox(
                width: _larguraColunaAcoes,
                child: Tooltip(
                  message: 'Ver detalhes',
                  child: IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: widget.onVerDetalhes,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
