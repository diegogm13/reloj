import 'dart:convert';

import 'package:http/http.dart' as http;

/// URL de la API de Chaac Xanab (la misma que usan la app y la web).
/// Para pruebas locales: flutter run --dart-define=API_URL=http://10.0.2.2:4300/api
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://backend-chaac-xanab.vercel.app/api');

class ZapatoRecomendado {
  final String nombre;
  final double precio;
  final double? precioOriginal;
  final List<String> tallas;
  final int stock;

  ZapatoRecomendado({
    required this.nombre,
    required this.precio,
    this.precioOriginal,
    required this.tallas,
    required this.stock,
  });

  factory ZapatoRecomendado.desdeJson(Map<String, dynamic> j) => ZapatoRecomendado(
    nombre: (j['name'] ?? '').toString(),
    precio: (j['price'] as num?)?.toDouble() ?? 0,
    precioOriginal: (j['original_price'] as num?)?.toDouble(),
    tallas: ((j['sizes'] as List?) ?? const []).map((e) => e.toString()).toList(),
    stock: (j['stock'] as num?)?.toInt() ?? 0,
  );
}

class RecomendacionException implements Exception {
  final String mensaje;
  RecomendacionException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Pide al catálogo los zapatos de running y elige uno disponible.
class RecomendacionService {
  final http.Client _http;
  RecomendacionService([http.Client? cliente]) : _http = cliente ?? http.Client();

  Future<ZapatoRecomendado> zapatoParaCorrer() async {
    final uri = Uri.parse('$apiUrl/productos').replace(queryParameters: {'categoria_slug': 'running'});
    final http.Response r;
    try {
      r = await _http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw RecomendacionException('Sin conexión');
    }
    if (r.statusCode != 200) throw RecomendacionException('La tienda no respondió (${r.statusCode})');

    final datos = jsonDecode(r.body);
    if (datos is! List) throw RecomendacionException('Respuesta inesperada');
    final disponibles = datos
        .whereType<Map<String, dynamic>>()
        .where((p) => (p['activo'] ?? true) == true)
        .map(ZapatoRecomendado.desdeJson)
        .where((z) => z.stock > 0)
        .toList();
    if (disponibles.isEmpty) throw RecomendacionException('No hay zapatos de running disponibles');
    // Prioriza los que tienen descuento y luego el más económico.
    disponibles.sort((a, b) {
      final da = a.precioOriginal != null && a.precioOriginal! > a.precio ? 0 : 1;
      final db = b.precioOriginal != null && b.precioOriginal! > b.precio ? 0 : 1;
      return da != db ? da - db : a.precio.compareTo(b.precio);
    });
    return disponibles.first;
  }
}

String precioTexto(double v) {
  final e = v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '\$$e';
}
