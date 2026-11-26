import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'firmware/detector_actividad.dart';
import 'servicios/recomendacion_service.dart';

void main() => runApp(const ChaacWearApp());

class ChaacColors {
  static const teal = Color(0xFF00A88F);
  static const tealOscuro = Color(0xFF005147);
  static const coral = Color(0xFFEA553B);
  static const gris = Color(0xFF9E9E9E);
}

class ChaacWearApp extends StatelessWidget {
  const ChaacWearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chaac Xanab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(seedColor: ChaacColors.tealOscuro, brightness: Brightness.dark),
      ),
      home: const PantallaReloj(),
    );
  }
}

class PantallaReloj extends StatefulWidget {
  const PantallaReloj({super.key});

  @override
  State<PantallaReloj> createState() => _PantallaRelojState();
}

class _PantallaRelojState extends State<PantallaReloj> {
  final _detector = DetectorActividad();
  final _servicio = RecomendacionService();
  final _paginas = PageController();
  final _reloj = Stopwatch();

  StreamSubscription<AccelerometerEvent>? _acelerometro;
  StreamSubscription<StepCount>? _contadorPasos;
  Timer? _loop;
  AccelerometerEvent? _ultimaLectura;

  bool _sensorPasosDisponible = false;
  int? _pasosBase;
  int _pasosSensor = 0;
  String? _avisoPermiso;
  bool _sinAcelerometro = false;

  /// Modo demostración (pulsación larga): alimenta el loop con un movimiento simulado,
  /// para presentar la app sin tener que correr con el reloj puesto.
  Actividad? _demo;

  ZapatoRecomendado? _zapato;
  String? _errorRecomendacion;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  /// setup(): se ejecuta una vez. Configura las "entradas" (sensores) y arranca el loop.
  Future<void> _setup() async {
    _detector
      ..alCambiar = _alCambiarEstado
      ..alRecomendar = _pedirRecomendacion;

    // Entrada principal: acelerómetro (no requiere permiso).
    _acelerometro = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) => _ultimaLectura = e, onError: (_) => setState(() => _sinAcelerometro = true), cancelOnError: true);

    // loop(): cada 40 ms lee la última lectura y ejecuta la máquina de estados.
    _reloj.start();
    _loop = Timer.periodic(const Duration(milliseconds: DetectorActividad.periodoMs), (_) {
      final t = _reloj.elapsedMilliseconds;
      final (double x, double y, double z) lectura;
      if (_demo != null) {
        final (hz, amp) = _demo == Actividad.corriendo ? (2.8, 6.0) : (1.8, 3.0);
        lectura = (0.3, 0.2, 9.81 + amp * sin(2 * pi * hz * t / 1000));
      } else {
        final e = _ultimaLectura;
        if (e == null) return;
        lectura = (e.x, e.y, e.z);
      }
      final antes = (_detector.pasos, _detector.actividad, _detector.cadencia.round());
      _detector.loop(lectura.$1, lectura.$2, lectura.$3, t);
      final despues = (_detector.pasos, _detector.actividad, _detector.cadencia.round());
      if (antes != despues && mounted) setState(() {});
    });

    // Entrada opcional: contador de pasos del reloj. Necesita el permiso de actividad física.
    final estado = await Permission.activityRecognition.request();
    if (!mounted) return;
    if (estado.isGranted) {
      _contadorPasos = Pedometer.stepCountStream.listen(
        (s) => setState(() {
          _pasosBase ??= s.steps;
          _pasosSensor = s.steps - _pasosBase!;
          _sensorPasosDisponible = true;
        }),
        onError: (_) => setState(() => _sensorPasosDisponible = false),
      );
    } else {
      setState(
        () => _avisoPermiso = estado.isPermanentlyDenied
            ? 'Permiso denegado: actívalo en Ajustes'
            : 'Sin permiso: pasos estimados',
      );
    }
  }

  /// Salida: al cambiar de estado el reloj vibra (como encender un LED con digitalWrite).
  void _alCambiarEstado(Actividad anterior, Actividad nueva) {
    if (nueva == Actividad.corriendo) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    if (mounted) setState(() {});
  }

  Future<void> _pedirRecomendacion() async {
    setState(() {
      _cargando = true;
      _errorRecomendacion = null;
    });
    try {
      final z = await _servicio.zapatoParaCorrer();
      if (!mounted) return;
      setState(() => _zapato = z);
      HapticFeedback.heavyImpact();
      _paginas.animateToPage(1, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    } on RecomendacionException catch (e) {
      if (mounted) setState(() => _errorRecomendacion = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Pulsación larga: Caminar → Correr → sensor real.
  void _cambiarDemo() {
    setState(
      () => _demo = switch (_demo) {
        null => Actividad.caminando,
        Actividad.caminando => Actividad.corriendo,
        _ => null,
      },
    );
    HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    _loop?.cancel();
    _acelerometro?.cancel();
    _contadorPasos?.cancel();
    _paginas.dispose();
    super.dispose();
  }

  Color get _color => switch (_detector.actividad) {
    Actividad.reposo => ChaacColors.gris,
    Actividad.caminando => ChaacColors.teal,
    Actividad.corriendo => ChaacColors.coral,
  };

  IconData get _icono => switch (_detector.actividad) {
    Actividad.reposo => Icons.accessibility_new,
    Actividad.caminando => Icons.directions_walk,
    Actividad.corriendo => Icons.directions_run,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onLongPress: _cambiarDemo,
        child: PageView(
          controller: _paginas,
          scrollDirection: Axis.vertical,
          children: [_paginaActividad(), _paginaRecomendacion()],
        ),
      ),
    );
  }

  Widget _paginaActividad() {
    final pasos = _sensorPasosDisponible && _demo == null ? _pasosSensor : _detector.pasos;
    final fuente = _demo != null
        ? 'DEMO: ${_demo == Actividad.corriendo ? 'corriendo' : 'caminando'}'
        : _sinAcelerometro
        ? 'Sin acelerómetro'
        : _sensorPasosDisponible
        ? 'Sensor de pasos'
        : (_avisoPermiso ?? 'Acelerómetro 25 Hz');
    return Stack(
      alignment: Alignment.center,
      children: [
        // Anillo de color: la "salida" visible del estado (como un LED).
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _color, width: 6),
          ),
        ),
        _areaSegura(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CHAAC XANAB',
                style: TextStyle(color: ChaacColors.teal, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
              ),
              const SizedBox(height: 6),
              Icon(_icono, color: _color, size: 34),
              Text(
                _detector.actividad.nombre,
                style: TextStyle(color: _color, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              Text('$pasos', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
              const Text('pasos', style: TextStyle(color: ChaacColors.gris, fontSize: 12)),
              const SizedBox(height: 4),
              Text('${_detector.cadencia.round()} pasos/min', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                fuente,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ChaacColors.gris, fontSize: 10),
              ),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Buscando tu zapato…', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cuadro inscrito en la pantalla redonda (≈ 70 % del diámetro): todo lo que va dentro
  /// se escala para no quedar cortado por las orillas, en cualquier tamaño de reloj.
  Widget _areaSegura(Widget hijo) {
    return LayoutBuilder(
      builder: (context, c) {
        final lado = c.biggest.shortestSide * 0.70;
        return Center(
          child: SizedBox.square(
            dimension: lado,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: 200, child: hijo),
            ),
          ),
        );
      },
    );
  }

  Widget _paginaRecomendacion() {
    final z = _zapato;
    Widget contenido;
    if (_cargando) {
      contenido = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(height: 8),
          Text('Consultando la tienda…', style: TextStyle(fontSize: 12)),
        ],
      );
    } else if (z != null) {
      final oferta = z.precioOriginal != null && z.precioOriginal! > z.precio;
      contenido = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PARA TU RITMO',
            style: TextStyle(color: ChaacColors.coral, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 6),
          Text(
            z.nombre,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                precioTexto(z.precio),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ChaacColors.teal),
              ),
              if (oferta) ...[
                const SizedBox(width: 6),
                Text(
                  precioTexto(z.precioOriginal!),
                  style: const TextStyle(fontSize: 12, color: ChaacColors.gris, decoration: TextDecoration.lineThrough),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            z.tallas.isEmpty ? 'Tallas en la app' : 'Tallas: ${z.tallas.take(5).join(' · ')}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: ChaacColors.gris),
          ),
          const SizedBox(height: 4),
          const Text('Cómpralo en la app Chaac Xanab', textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
        ],
      );
    } else {
      contenido = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_errorRecomendacion == null ? Icons.directions_run : Icons.wifi_off, color: ChaacColors.coral, size: 28),
          const SizedBox(height: 6),
          Text(
            _errorRecomendacion ?? 'Corre 10 segundos y te recomendamos un zapato',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _pedirRecomendacion,
            style: FilledButton.styleFrom(
              backgroundColor: ChaacColors.tealOscuro,
                foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(_errorRecomendacion == null ? 'Ver ahora' : 'Reintentar', style: const TextStyle(fontSize: 12)),
          ),
        ],
      );
    }
    return _areaSegura(Center(child: contenido));
  }
}
