/// Backend de física ODE para el contrato `PhysicsSimulation` de `package:scene`.
///
/// Desde el 2026-09-17 este plugin es una CÁSCARA: el código vive en
/// `core/` (`flutter_scene_ode_core`, Dart puro) y aquí solo quedan las dos cosas que
/// necesitan a Flutter —empaquetar el `.so`, el `.wasm` y las plataformas, y
/// bajar el módulo de wasm del `rootBundle` en web—. Así el evaluador de
/// concursos (un binario sin pantalla) corre la MISMA física que el teléfono
/// sin arrastrar el SDK de Flutter, y nadie que importe `flutter_scene_ode` nota el
/// cambio: la superficie pública es la de siempre, re-exportada.
library;

export 'package:flutter_scene_ode_core/flutter_scene_ode_core.dart';

export 'src/flutter_scene_ode_bundle.dart';
