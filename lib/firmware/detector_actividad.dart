import 'dart:math';

/// Estados de la máquina de estados del reloj.
enum Actividad { reposo, caminando, corriendo }

extension ActividadTexto on Actividad {
  String get nombre => switch (this) {
    Actividad.reposo => 'REPOSO',
    Actividad.caminando => 'CAMINANDO',
    Actividad.corriendo => 'CORRIENDO',
  };
}

/// "Firmware" del reloj (Práctica 1 aplicada a un wearable).
///
/// Sigue la misma estructura que un programa de microcontrolador:
///  - [setup] se ejecuta una vez: deja las variables y la calibración en su valor inicial.
///  - [loop] se ejecuta continuamente (cada [periodoMs]) con la última lectura del sensor,
///    como `digitalRead()` dentro de `loop()`.
///  - Una máquina de estados (REPOSO → CAMINANDO → CORRIENDO) decide qué hacer, con un
///    tiempo de confirmación para no cambiar por una lectura suelta (como el antirrebote de un botón).
///
/// No depende de Flutter: se puede probar con lecturas simuladas.
class DetectorActividad {
  /// Periodo del loop en milisegundos (25 lecturas por segundo).
  static const int periodoMs = 40;

  /// Umbral de la aceleración dinámica (m/s²) para contar un paso.
  static const double umbralPaso = 1.2;

  /// Tiempo mínimo entre dos pasos (evita contar el mismo paso dos veces).
  static const int separacionMinMs = 250;

  /// Ventana para calcular la cadencia (pasos por minuto).
  static const int ventanaMs = 6000;

  /// Cadencias que separan los estados.
  static const double cadenciaCaminar = 40;
  static const double cadenciaCorrer = 140;

  /// Tiempo que un estado nuevo debe mantenerse antes de aceptarse.
  static const int confirmacionMs = 3000;

  /// Tiempo corriendo para recomendar un zapato de running.
  static const int corriendoParaRecomendarMs = 10000;

  // ---- Estado interno (equivalente a las variables globales de un firmware) ----
  late double _gravedad;
  late bool _sobreUmbral;
  late int _ultimoPasoMs;
  late List<int> _pasosRecientes;
  late int pasos;
  late Actividad actividad;
  late Actividad? _candidata;
  late int _candidataDesdeMs;
  late int _actividadDesdeMs;
  late bool recomendacionPedida;
  int _ahoraMs = 0;

  /// Se llama cuando la máquina cambia de estado (el reloj vibra, como encender un LED).
  void Function(Actividad anterior, Actividad nueva)? alCambiar;

  /// Se llama una sola vez cuando se lleva [corriendoParaRecomendarMs] corriendo.
  void Function()? alRecomendar;

  DetectorActividad() {
    setup();
  }

  /// Configuración inicial: se ejecuta una vez al encender (como `setup()`).
  void setup() {
    _gravedad = 9.81;
    _sobreUmbral = false;
    _ultimoPasoMs = -separacionMinMs;
    _pasosRecientes = [];
    pasos = 0;
    actividad = Actividad.reposo;
    _candidata = null;
    _candidataDesdeMs = 0;
    _actividadDesdeMs = 0;
    recomendacionPedida = false;
    _ahoraMs = 0;
  }

  /// Si no hay un paso en este tiempo, se considera que la persona se detuvo.
  static const int sinPasosMs = 2000;

  /// Pasos por minuto en la última ventana (0 si ya no hay pasos recientes).
  double get cadencia {
    if (_ahoraMs - _ultimoPasoMs > sinPasosMs) return 0;
    final desde = _ahoraMs - ventanaMs;
    final n = _pasosRecientes.where((t) => t > desde).length;
    return n * 60000 / ventanaMs;
  }

  /// Una vuelta del loop con la lectura más reciente del acelerómetro (m/s²).
  /// [ahoraMs] es el tiempo transcurrido desde el arranque.
  void loop(double x, double y, double z, int ahoraMs) {
    _ahoraMs = ahoraMs;

    // 1. Leer la entrada: magnitud de la aceleración.
    final magnitud = sqrt(x * x + y * y + z * z);

    // 2. Filtrar: un filtro paso bajo sigue la gravedad (la línea base, como INPUT_PULLUP
    //    da un valor estable en reposo); lo que sobra es el movimiento del brazo.
    _gravedad = 0.9 * _gravedad + 0.1 * magnitud;
    final dinamica = magnitud - _gravedad;

    // 3. Detectar un paso en el flanco de subida sobre el umbral (como detectar que se presionó un botón).
    if (!_sobreUmbral && dinamica > umbralPaso && ahoraMs - _ultimoPasoMs >= separacionMinMs) {
      _sobreUmbral = true;
      _ultimoPasoMs = ahoraMs;
      pasos++;
      _pasosRecientes.add(ahoraMs);
    } else if (_sobreUmbral && dinamica < umbralPaso * 0.5) {
      _sobreUmbral = false;
    }
    _pasosRecientes.removeWhere((t) => t <= ahoraMs - ventanaMs);

    // 4. Máquina de estados con confirmación.
    final propuesta = _clasificar(cadencia);
    if (propuesta == actividad) {
      _candidata = null;
    } else if (propuesta != _candidata) {
      _candidata = propuesta;
      _candidataDesdeMs = ahoraMs;
    } else if (ahoraMs - _candidataDesdeMs >= confirmacionMs) {
      final anterior = actividad;
      actividad = propuesta;
      _actividadDesdeMs = ahoraMs;
      _candidata = null;
      alCambiar?.call(anterior, actividad);
    }

    // 5. Actuar: tras correr un rato, pedir una recomendación una sola vez.
    if (actividad == Actividad.corriendo &&
        !recomendacionPedida &&
        ahoraMs - _actividadDesdeMs >= corriendoParaRecomendarMs) {
      recomendacionPedida = true;
      alRecomendar?.call();
    }
  }

  Actividad _clasificar(double cadencia) {
    if (cadencia >= cadenciaCorrer) return Actividad.corriendo;
    if (cadencia >= cadenciaCaminar) return Actividad.caminando;
    return Actividad.reposo;
  }
}
