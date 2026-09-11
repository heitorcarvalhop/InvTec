import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/responsive/breakpoints.dart';

void main() {
  test('largura abaixo de 600 é mobile', () {
    expect(Breakpoints.of(0), ScreenSize.mobile);
    expect(Breakpoints.of(599.9), ScreenSize.mobile);
  });

  test('largura entre 600 e 1024 é tablet', () {
    expect(Breakpoints.of(600), ScreenSize.tablet);
    expect(Breakpoints.of(1023.9), ScreenSize.tablet);
  });

  test('largura a partir de 1024 é desktop', () {
    expect(Breakpoints.of(1024), ScreenSize.desktop);
    expect(Breakpoints.of(1920), ScreenSize.desktop);
  });
}
