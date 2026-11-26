import 'dart:math';

import 'package:chaac_xanab_wear/firmware/detector_actividad.dart';
import 'package:chaac_xanab_wear/servicios/recomendacion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Simula el brazo moviéndose a [hz] pasos por segundo con amplitud [amp] (m/s²).
void simular(
  DetectorActividad d, {
  required double hz,
  required double amp,
  required int desdeMs,
  required int duracionMs,
}) {
  for (var t = desdeMs; t < desdeMs + duracionMs; t += DetectorActividad.periodoMs) {
    final z = 9.81 + amp * sin(2 * pi * hz * t / 1000);
    d.loop(0.3, 0.2, z, t);
  }
}

void main() {
  group('Firmware del reloj (setup/loop + máquina de estados)', () {
    test('setup deja el detector en reposo y sin pasos', () {
      final d = DetectorActividad();
      expect(d.actividad, Actividad.reposo);
      expect(d.pasos, 0);
    });

    test('quieto: se queda en REPOSO y no cuenta pasos', () {
      final d = DetectorActividad();
      simular(d, hz: 0, amp: 0, desdeMs: 0, duracionMs: 10000);
      expect(d.actividad, Actividad.reposo);
      expect(d.pasos, 0);
    });

    test('caminar a ~1.8 pasos/s pasa a CAMINANDO y cuenta un paso por ciclo', () {
      final d = DetectorActividad();
      final cambios = <Actividad>[];
      d.alCambiar = (_, n) => cambios.add(n);
      simular(d, hz: 1.8, amp: 3, desdeMs: 0, duracionMs: 12000);
      expect(d.actividad, Actividad.caminando);
      expect(cambios, [Actividad.caminando]);
      expect(d.pasos, inInclusiveRange(19, 22)); // 1.8 × 12 s ≈ 21
      expect(d.cadencia, inInclusiveRange(100, 120));
    });

    test('correr a ~2.8 pasos/s pasa a CORRIENDO y pide una sola recomendación', () {
      final d = DetectorActividad();
      var recomendaciones = 0;
      d.alRecomendar = () => recomendaciones++;
      simular(d, hz: 2.8, amp: 6, desdeMs: 0, duracionMs: 25000);
      expect(d.actividad, Actividad.corriendo);
      expect(d.cadencia, greaterThanOrEqualTo(DetectorActividad.cadenciaCorrer));
      expect(recomendaciones, 1);
    });

    test('un movimiento suelto no cambia el estado (confirmación de 3 s)', () {
      final d = DetectorActividad();
      simular(d, hz: 2.8, amp: 6, desdeMs: 0, duracionMs: 1500);
      simular(d, hz: 0, amp: 0, desdeMs: 1500, duracionMs: 4000);
      expect(d.actividad, Actividad.reposo);
    });

    test('al dejar de correr vuelve a REPOSO', () {
      final d = DetectorActividad();
      simular(d, hz: 2.8, amp: 6, desdeMs: 0, duracionMs: 12000);
      simular(d, hz: 0, amp: 0, desdeMs: 12000, duracionMs: 12000);
      expect(d.actividad, Actividad.reposo);
    });
  });

  group('Recomendación desde la API', () {
    test('elige un zapato de running disponible, primero los de oferta', () async {
      final cliente = MockClient((req) async {
        expect(req.url.queryParameters['categoria_slug'], 'running');
        return http.Response(
          '[{"name":"Agotado","price":900,"stock":0,"activo":true,"sizes":["26"]},'
          '{"name":"Normal","price":1200,"stock":4,"activo":true,"sizes":["26","27"]},'
          '{"name":"Oferta","price":1500,"original_price":2000,"stock":2,"activo":true,"sizes":["27"]}]',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final z = await RecomendacionService(cliente).zapatoParaCorrer();
      expect(z.nombre, 'Oferta');
      expect(precioTexto(z.precio), r'$1,500');
    });

    test('error del servidor y sin red dan mensajes controlados', () async {
      expect(
        () => RecomendacionService(MockClient((_) async => http.Response('{}', 500))).zapatoParaCorrer(),
        throwsA(isA<RecomendacionException>().having((e) => e.mensaje, 'mensaje', contains('500'))),
      );
      expect(
        () => RecomendacionService(MockClient((_) async => throw Exception('sin red'))).zapatoParaCorrer(),
        throwsA(isA<RecomendacionException>().having((e) => e.mensaje, 'mensaje', 'Sin conexión')),
      );
    });
  });
}
