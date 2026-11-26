# Chaac Xanab para reloj (Wear OS)

App de reloj de la tienda Chaac Xanab. Aplica la **Práctica 1 (firmware mediante script)** a un wearable:

- `setup()` configura los sensores una sola vez (acelerómetro y, si hay permiso, el contador de pasos del reloj).
- `loop()` corre cada 40 ms (25 veces por segundo): lee el acelerómetro, filtra la gravedad y detecta pasos.
- Una **máquina de estados** decide si la persona está en `REPOSO`, `CAMINANDO` o `CORRIENDO`, con 3 s de confirmación.
- **Salidas:** el anillo de la pantalla cambia de color y el reloj vibra en cada cambio de estado.
- Tras **10 s corriendo** consulta la API de la tienda (`GET /api/productos?categoria_slug=running`) y recomienda un zapato de running disponible (primero los de oferta).

El código del "firmware" está en `lib/firmware/detector_actividad.dart` y no depende de Flutter, por eso se prueba con señales simuladas en `test/`.

## Modo demostración

Mantén presionada la pantalla para cambiar entre **Caminar → Correr → Sensor real**. El loop recibe un movimiento simulado en lugar del acelerómetro; sirve para presentar la app sin correr con el reloj puesto y para probarla en el emulador, que no reproduce bien el movimiento.

## Probar

```powershell
flutter test
```

## Desplegar en un reloj o en el emulador

1. Arranca el emulador Wear OS (o conecta el reloj por depuración inalámbrica):
   ```powershell
   & "C:\Android\sdk\emulator\emulator.exe" -avd Wear_OS_5
   ```
2. Compila el APK de release (usa la API de producción):
   ```powershell
   flutter build apk --release
   ```
3. Instálalo:
   ```powershell
   adb install -r build\app\outputs\flutter-apk\app-release.apk
   ```

Para apuntar a una API local (por ejemplo, desde el emulador a tu PC):

```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:3000/api
```

**Pendiente:** el release se firma con la llave de depuración, igual que la app del teléfono. Para publicarlo en Play Store hace falta una llave propia (`android/key.properties`).
