import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene_ode_core/src/ode/ode_library_web.dart';

/// Le dice al núcleo de dónde salen `ode.js` y `ode.wasm`: de los assets de
/// ESTE plugin. Idempotente.
void instalar() {
  odeModuleLoader ??= () async => (
        glue: await rootBundle.loadString('packages/flutter_scene_ode/assets/ode.js'),
        wasm: (await rootBundle.load('packages/flutter_scene_ode/assets/ode.wasm'))
            .buffer
            .asUint8List(),
      );
}
