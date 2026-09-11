import 'package:flutter/material.dart';

/// Campo de data (sem hora) somente até hoje — usado em "Data de
/// aquisição". Não é uma regra do banco (a coluna aceita qualquer `date`),
/// mas evitar datas futuras aqui é uma escolha razoável de UX: adquirir um
/// equipamento "no futuro" não faz sentido operacional.
class DateOnlyField extends StatelessWidget {
  const DateOnlyField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _selecionar(BuildContext context) async {
    final hoje = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: value ?? hoje,
      firstDate: DateTime(2000),
      lastDate: hoje,
    );
    if (escolhida != null) onChanged(escolhida);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _selecionar(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined)
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: enabled ? () => onChanged(null) : null,
                ),
        ),
        child: Text(value == null ? 'Não informada' : _formatar(value!)),
      ),
    );
  }
}

String _formatar(DateTime data) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(data.day)}/${pad(data.month)}/${data.year}';
}
