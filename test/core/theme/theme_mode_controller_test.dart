import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:invtec/core/theme/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Store local em memória, isolado entre testes (PROMPT 9.3).
    SharedPreferences.setMockInitialValues({});
  });

  test('sem preferência salva, inicia em tema claro', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final modo = await container.read(themeModeControllerProvider.future);

    expect(modo, ThemeMode.light);
  });

  test('inicia com a preferência persistida (escuro)', () async {
    SharedPreferences.setMockInitialValues({'invtec.theme_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final modo = await container.read(themeModeControllerProvider.future);

    expect(modo, ThemeMode.dark);
  });

  test('alternar() claro -> escuro muda o estado imediatamente', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeModeControllerProvider.future);

    await container.read(themeModeControllerProvider.notifier).alternar();

    expect(container.read(themeModeControllerProvider).value, ThemeMode.dark);
  });

  test('alternar() escuro -> claro muda o estado imediatamente', () async {
    SharedPreferences.setMockInitialValues({'invtec.theme_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeModeControllerProvider.future);

    await container.read(themeModeControllerProvider.notifier).alternar();

    expect(container.read(themeModeControllerProvider).value, ThemeMode.light);
  });

  test('definir() persiste a escolha para uma nova instância do provider (recriação do app)', () async {
    final container1 = ProviderContainer();
    await container1.read(themeModeControllerProvider.future);
    await container1.read(themeModeControllerProvider.notifier).definir(ThemeMode.dark);
    container1.dispose();

    // Simula reabrir o app: um container/provider totalmente novo.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final modoRestaurado = await container2.read(themeModeControllerProvider.future);

    expect(modoRestaurado, ThemeMode.dark);
  });
}
