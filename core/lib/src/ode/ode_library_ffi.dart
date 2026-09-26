// Carga de `libode` con FALLO BLANDO.
//
// Por qué blando y no una excepción: el constructor del mecano es
// inherentemente 3D y no tiene versión 2D. Un dispositivo sin el `.so` (ABI que
// no es arm64-v8a, o escritorio sin la librería) tiene que poder enseñar la
// pantalla honesta «este dispositivo no puede abrir el constructor», y para eso
// hay que poder PREGUNTAR si ODE está disponible sin que preguntar reviente el
// frame. Por eso nada de aquí lanza: se cachea el motivo y se devuelve null.
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

// Los bindings NATIVOS, directamente y no por el barrel condicional: esta cara
// solo existe donde hay `dart:ffi`, y pasar por el barrel la haría resolverse
// por la rama web (que es la de por defecto) y verse roja entera.
import 'ode_bindings_ffi.dart';

ffi.DynamicLibrary? _cached;
String? _reason;
bool _tried = false;

/// La biblioteca nativa, o null si no se pudo cargar. Nunca lanza.
ffi.DynamicLibrary? openOdeLibrary() {
  if (_tried) return _cached;
  _tried = true;

  final attempts = <String>[];

  // 1) Override explícito. Es lo que usa el banco de tests de host, que corre
  //    contra el libode compilado por `tool/build_ode.sh host` — sin Android,
  //    sin emulador y sin qemu.
  final override = Platform.environment['ODE_LIBRARY_PATH'];
  if (override != null && override.isNotEmpty) {
    try {
      _cached = ffi.DynamicLibrary.open(override);
      return _cached;
    } catch (e) {
      attempts.add('ODE_LIBRARY_PATH=$override: $e');
    }
  }

  // 2) El proceso. Es EL camino de Apple: el pod `flutter_scene_ode` se construye
  //    como framework dinámico y el Runner lo enlaza, así que sus símbolos
  //    están cargados desde el arranque y `process()` (que es
  //    dlopen(NULL)) los ve. Vale igual si algún día se enlazara estático,
  //    que es el patrón del compilador nativo de Nairda.
  if (!Platform.isAndroid && !Platform.isWindows) {
    try {
      final process = ffi.DynamicLibrary.process();
      process.lookup<ffi.NativeFunction<ffi.Void Function(ffi.Int)>>(
        'dInitODE2',
      );
      _cached = process;
      return _cached;
    } catch (e) {
      attempts.add('process(): $e');
    }
  }

  // 3) Por nombre. En Android el linker la saca de jniLibs/<abi>/. En Apple el
  //    binario NO se llama libode.dylib: vive dentro del framework del pod y
  //    se llama como el pod. Este intento es solo una red — el que resuelve de
  //    verdad allí es el (2).
  final name = Platform.isWindows
      ? 'ode.dll'
      : Platform.isMacOS || Platform.isIOS
          ? 'flutter_scene_ode.framework/flutter_scene_ode'
          : 'libode.so';
  try {
    _cached = ffi.DynamicLibrary.open(name);
    return _cached;
  } catch (e) {
    attempts.add('open($name): $e');
  }

  _reason = 'no se pudo cargar libode (${Platform.operatingSystem}): '
      '${attempts.join(' | ')}';
  return null;
}

/// Por qué no está disponible, para enseñárselo a alguien. null si sí lo está.
String? get odeUnavailableReason {
  openOdeLibrary();
  return _reason;
}

/// Comprueba que el binario cargado es el que los bindings creen que es.
///
/// Los bindings declaran `dReal = ffi.Float`. Un `.so` compilado en doble
/// precisión **no da ningún error de enlace**: las llamadas cuadran y los
/// valores salen basura. Este es el único sitio donde eso se puede cazar, y
/// cuesta una llamada al arrancar.
void assertOdeAbi(OdeBindings ode) {
  final token = 'ODE_single_precision'.toNativeUtf8();
  try {
    if (ode.dCheckConfiguration(token.cast()) == 0) {
      final cfg = ode.dGetConfiguration();
      final text = cfg == ffi.nullptr ? '(desconocida)' : cfg.cast<Utf8>().toDartString();
      throw StateError(
        'libode NO es single precision, pero los bindings tienen '
        'dReal = ffi.Float clavado: leería basura. '
        'Recompilar con -DODE_DOUBLE_PRECISION=OFF (ver NATIVE.md). '
        'dGetConfiguration() = "$text"',
      );
    }
  } finally {
    calloc.free(token);
  }
}

/// El gemelo de la cara web, aquí trivial: en nativo abrir la librería es
/// síncrono, así que esto solo la abre y devuelve un futuro ya completado.
/// Existe para que la costura tenga la misma forma en las dos ramas y el
/// consumidor no tenga que saber en cuál está.
Future<void> ensureOdeLibrary() async {
  openOdeLibrary();
}
