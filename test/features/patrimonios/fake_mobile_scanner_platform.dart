import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Fake de [MobileScannerPlatform] para testar `PatrimonioScannerPage` sem
/// câmera/hardware real — mesmo padrão usado pelos testes do próprio
/// pacote `mobile_scanner` (`test/mobile_scanner_widget/detect_barcode_test.dart`,
/// no pub cache): [MobileScannerPlatform.instance] é um singleton
/// substituível, então um teste de widget consegue simular detecções de
/// barcode (via [detectar]) e falha de inicialização (via [erroAoIniciar],
/// ex.: permissão negada) sem nenhum dispositivo físico.
class FakeMobileScannerPlatform extends MobileScannerPlatform {
  FakeMobileScannerPlatform({this.erroAoIniciar});

  /// Quando definido, [start] lança este erro em vez de "ligar a câmera"
  /// — simula permissão negada ou dispositivo sem câmera compatível.
  final MobileScannerException? erroAoIniciar;

  final _barcodes = StreamController<BarcodeCapture>.broadcast();
  final _torchState = StreamController<TorchState>.broadcast();

  int startCallCount = 0;
  int stopCallCount = 0;
  int disposeCallCount = 0;
  int toggleTorchCallCount = 0;
  TorchState _torch = TorchState.off;

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => _torchState.stream;

  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    startCallCount++;
    final erro = erroAoIniciar;
    if (erro != null) throw erro;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(200, 200),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> toggleTorch() async {
    toggleTorchCallCount++;
    _torch = _torch == TorchState.on ? TorchState.off : TorchState.on;
    _torchState.add(_torch);
  }

  @override
  Widget buildCameraView() => const SizedBox.square(dimension: 100);

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    await _barcodes.close();
    await _torchState.close();
  }

  /// Simula a câmera detectando uma etiqueta com [rawValue].
  void detectar(String rawValue) {
    _barcodes.add(BarcodeCapture(barcodes: [Barcode(rawValue: rawValue)]));
  }
}
