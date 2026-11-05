import 'dart:typed_data';

import 'package:fatigue_guard/vision/vision_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YUV_420 com stride é convertido para NV21 (Y + VU intercalado)', () {
    const w = 4, h = 2;
    // Y com rowStride 6 (2 bytes de preenchimento por linha).
    final y = Uint8List.fromList([1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0]);
    // U e V com pixelStride 2 (formato semi‑planar comum em Android).
    final u = Uint8List.fromList([10, 99, 11, 99]);
    final v = Uint8List.fromList([20, 99, 21, 99]);
    final nv21 = yuv420ToNv21(w, h, [YuvPlane(y, 6, 1), YuvPlane(u, 4, 2), YuvPlane(v, 4, 2)]);
    expect(nv21, [1, 2, 3, 4, 5, 6, 7, 8, 20, 10, 21, 11]);
    expect(nv21.length, w * h * 3 ~/ 2);
  });
}
