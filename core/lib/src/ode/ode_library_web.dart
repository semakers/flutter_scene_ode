/// La carga del backend en web: descargar el `.wasm`, instanciarlo y dejar el
/// heap listo para el shim.
///
/// Mantiene el contrato de la cara nativa, incluido lo más importante: **el
/// FALLO BLANDO**. Nada de aquí lanza nunca. Si algo va mal se cachea el motivo
/// y [openOdeLibrary] devuelve null, que es lo que alimenta la pantalla «este
/// dispositivo no puede abrir el constructor». El camino triste no necesita
/// código nuevo: es el mismo que ya existía cuando web no tenía física.
///
/// La única diferencia real con la rama nativa es que aquí la carga es
/// ASÍNCRONA, y por eso existe [ensureOdeLibrary]. `isAvailable` sigue siendo
/// un getter síncrono; antes de esperar a `ensureOdeLibrary` dice, con razón,
/// que no está.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';


import 'ffi_shim_web.dart';
import 'ode_bindings_web.dart';

// -------------------------------------------------------------- DOM mínimo
// Declarado a mano en vez de con `package:web` para no añadir una dependencia
// por tres miembros.

@JS('document')
external _Document get _document;

@JS('globalThis')
external JSObject get _globalThis;

extension type _Document._(JSObject _) implements JSObject {
  external _Element createElement(String tag);
  external _Element get head;
}

extension type _Element._(JSObject _) implements JSObject {
  external set textContent(String v);
  external void appendChild(_Element child);
}

extension type _ModuleOptions._(JSObject _) implements JSObject {
  external factory _ModuleOptions({JSUint8Array wasmBinary});
}

// ------------------------------------------------------------------ estado

DynamicLibrary? _cached;
String? _reason;
Future<void>? _enCurso;

/// Bytes inyectados a mano, para los bancos de prueba.
///
/// `flutter test --platform chrome` no siempre sirve los assets del paquete, y
/// atarse a `rootBundle` dejaría el banco de física sin poder correr contra
/// wasm. Con esto, quien pruebe puede darle el módulo y saltarse el bundle.
({String glue, Uint8List wasm})? debugOdeModuleBytes;

/// Quién trae el módulo en la app: lo pone el PLUGIN (`flutter_scene_ode`), que es
/// el que tiene el `rootBundle` y los assets. Este paquete es Dart puro y no
/// sabe qué es un bundle; sin cargador y sin bytes inyectados, la física en web
/// «no está», con su motivo, igual que en un dispositivo sin binario.
Future<({String glue, Uint8List wasm})> Function()? odeModuleLoader;

/// Igual que en la rama nativa: síncrono, nunca lanza, null si no hay backend.
///
/// En web devuelve null hasta que [ensureOdeLibrary] haya terminado.
DynamicLibrary? openOdeLibrary() => _cached;

String? get odeUnavailableReason {
  if (_cached != null) return null;
  return _reason ??
      'ODE en web todavía no está cargado: falta esperar a '
          'OdeSimulation.ensureAvailable() antes de preguntar.';
}

/// Carga el módulo. Idempotente y memoizada: llamarla dos veces no descarga dos
/// veces, y llamarla mientras está en curso espera a la misma.
Future<void> ensureOdeLibrary() {
  if (_cached != null || _reason != null) return Future<void>.value();
  return _enCurso ??= _cargar();
}

Future<void> _cargar() async {
  try {
    final inyectado = debugOdeModuleBytes;
    final cargador = odeModuleLoader;
    if (inyectado == null && cargador == null) {
      _reason = 'nadie instaló el cargador del módulo de ODE en web '
          '(el plugin flutter_scene_ode lo hace en FlutterSceneOde.ensureAvailable)';
      return;
    }
    final modulo = inyectado ?? await cargador!();
    final glue = modulo.glue;
    final wasm = modulo.wasm;

    // El glue se ejecuta como script EN LÍNEA, no desde una URL. Es
    // deliberado: una URL habría que resolverla contra el <base href>, que en
    // esta app vale «/» en local, «/app/» en producción y «/develop/» en las
    // pruebas — y equivocarse ahí no da ningún error HTTP, da una página que no
    // carga la física y nadie sabe por qué. Los bytes ya los tenemos.
    if (_globalThis.getProperty<JSAny?>('createNairdaOde'.toJS) == null) {
      final script = _document.createElement('script');
      script.textContent = glue;
      _document.head.appendChild(script);
    }
    final factory =
        _globalThis.getProperty<JSAny?>('createNairdaOde'.toJS) as JSFunction?;
    if (factory == null) {
      _reason = 'ode.js se cargó pero no definió createNairdaOde '
          '(¿una CSP que prohíbe scripts en línea?)';
      return;
    }

    // `wasmBinary`: los bytes van directos, sin que el módulo tenga que ir a
    // buscar el .wasm por su cuenta. Va declarado en INCOMING_MODULE_JS_API del
    // enlace; sin declararlo, la variante con ASSERTIONS aborta (y la de
    // release lo aceptaba en silencio, que es peor).
    // `callAsFunction` y NO un miembro `external call(...)`: un método llamado
    // `call` en interop resuelve a `Function.prototype.call`, que se come el
    // primer argumento como `this`. El módulo se instanciaba SIN opciones, no
    // veía `wasmBinary` y se iba a buscar el .wasm por URL — que es justo lo
    // que este camino existe para no hacer. El síntoma era «both async and
    // sync fetching of the wasm failed», que no menciona el argumento perdido.
    final module = await (factory.callAsFunction(
      null,
      _ModuleOptions(wasmBinary: wasm.toJS),
    )! as JSPromise<JSObject>)
        .toDart;

    odeHeap = OdeHeap(module);
    final lib = DynamicLibrary(module);

    final problema = _cotejarModulo(lib);
    if (problema != null) {
      _reason = problema;
      return;
    }

    odeSizes.addAll(odeStructSizes);
    _cached = lib;
  } catch (e) {
    // Fallo BLANDO, como en nativo: el motivo se enseña, no se lanza.
    _reason = 'no se pudo cargar ode.wasm: $e';
  }
}

/// Las tres comprobaciones que separan «cargó» de «cargó lo correcto».
String? _cotejarModulo(DynamicLibrary lib) {
  final ode = OdeBindings(lib);

  // 1. EL LAYOUT. wasm32 es ILP32 y los desplazamientos que este paquete lleva
  //    generados salieron de UN módulo concreto. Si el .wasm de assets/ es de
  //    otra compilación, los campos se leerían corridos y la física se movería
  //    mal sin dar un error. Se le pregunta al módulo que se acaba de cargar.
  final vivo = _layoutDelModulo(ode);
  for (final e in odeGeneratedLayout.entries) {
    if (vivo[e.key] != e.value) {
      return 'el ode.wasm de assets/ no cuadra con los bindings generados: '
          '${e.key} vale ${vivo[e.key]} y se generó con ${e.value}. '
          'Corre tool/build_ode_wasm.sh y luego dart tool/gen_bindings_web.dart.';
    }
  }

  // 2. EL HEAP DE VERDAD. `JSFloat32Array.toDart` es una VISTA sin copia en
  //    dart2js pero una COPIA en dart2wasm. Con la copia, todo lo que
  //    escribiera el shim iría a un sitio que ODE no lee jamás: la física se
  //    quedaría quieta, sin un solo error en consola. Así que se escribe por un
  //    camino y se lee por el otro, en los dos sentidos.
  final sonda = odeHeap.module.callMethod<JSNumber>('_malloc'.toJS, 8.toJS).toDartInt;
  try {
    odeHeap.setF32(sonda, 1234.5);
    final leidoJs = (odeHeap.module.getProperty<JSFloat32Array>('HEAPF32'.toJS))
        .toDart[sonda >> 2];
    if ((leidoJs - 1234.5).abs() > 1e-6) {
      return 'el heap de wasm no es visible desde Dart (escribí 1234.5 y JS lee '
          '$leidoJs). Suele ser dart2wasm con la vista copiada.';
    }
    odeHeap.setI32(sonda + 4, 0x5A5A5A);
    if (odeHeap.getI32(sonda + 4) != 0x5A5A5A) {
      return 'el heap de wasm no conserva lo que se le escribe.';
    }
  } finally {
    odeHeap.module.callMethod<JSAny?>('_free'.toJS, sonda.toJS);
  }

  // 3. LA PRECISIÓN, que es la de siempre.
  try {
    assertOdeAbi(ode);
  } on StateError catch (e) {
    return e.message;
  }
  return null;
}

Map<String, int> _layoutDelModulo(OdeBindings ode) {
  final m = odeHeap.module;
  final n = m.callMethod<JSNumber>('_nairda_ode_layout_count'.toJS).toDartInt;
  final buf = m.callMethod<JSNumber>('_malloc'.toJS, (n * 4).toJS).toDartInt;
  try {
    m.callMethod<JSNumber>('_nairda_ode_layout'.toJS, buf.toJS, n.toJS);
    final nombres = odeHeap
        .readCString(
            m.callMethod<JSNumber>('_nairda_ode_layout_names'.toJS).toDartInt)
        .split('\n')
        .where((s) => s.isNotEmpty)
        .toList();
    return {
      for (var i = 0; i < nombres.length && i < n; i++)
        nombres[i]: odeHeap.getI32(buf + i * 4),
    };
  } finally {
    m.callMethod<JSAny?>('_free'.toJS, buf.toJS);
  }
}

/// La misma guardia que en nativo: un módulo en doble precisión no daría error
/// de enlace, LEERÍA BASURA, porque los bindings tienen `dReal = Float`
/// clavado.
///
/// Aquí la cadena se escribe a mano en el heap en vez de con `toNativeUtf8`:
/// son veinte bytes ASCII y así no hay que exportar los ayudantes de string de
/// emscripten.
void assertOdeAbi(OdeBindings ode) {
  const token = 'ODE_single_precision';
  final p = odeHeap.module
      .callMethod<JSNumber>('_malloc'.toJS, (token.length + 1).toJS)
      .toDartInt;
  try {
    for (var i = 0; i < token.length; i++) {
      odeHeap.setU8(p + i, token.codeUnitAt(i));
    }
    odeHeap.setU8(p + token.length, 0);
    if (ode.dCheckConfiguration(Pointer<Char>(p)) == 0) {
      final cfg = ode.dGetConfiguration();
      final texto =
          cfg.address == 0 ? '(desconocida)' : odeHeap.readCString(cfg.address);
      throw StateError(
        'ode.wasm NO es single precision, pero los bindings tienen '
        'dReal = Float clavado: leería basura. Recompilar con dIDESINGLE '
        '(ver NATIVE.md). dGetConfiguration() = "$texto"',
      );
    }
  } finally {
    odeHeap.module.callMethod<JSAny?>('_free'.toJS, p.toJS);
  }
}
