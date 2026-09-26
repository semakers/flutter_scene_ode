/// La puerta del plugin: lo mismo que `OdeSimulation.ensureAvailable`, pero
/// dejando antes instalado el cargador del módulo de wasm, que es lo único que
/// el núcleo puro no puede hacer por sí mismo (no sabe qué es un `rootBundle`).
///
/// En las plataformas nativas `_instalar` no hace nada y esto es exactamente
/// `OdeSimulation.ensureAvailable()`.
library;

import 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';

import 'bundle_stub.dart' if (dart.library.js_interop) 'bundle_web.dart'
    as bundle;

abstract final class FlutterSceneOde {
  static Future<void> ensureAvailable() {
    bundle.instalar();
    return OdeSimulation.ensureAvailable();
  }
}
