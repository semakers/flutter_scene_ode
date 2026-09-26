// El arranque del banco en el navegador: inyectarle al cargador los bytes del
// módulo.
//
// Hace falta porque `flutter test --platform chrome` NO sirve el bundle de
// assets —flutter_web_platform.dart no lo menciona— así que `rootBundle` se
// queda esperando y el test muere por timeout a los 30 s con una traza que no
// habla de assets. Los bytes viajan en base64 dentro del propio banco, y
// tool/vendor_wasm.sh los regenera del mismo .wasm que va en assets/.
import 'dart:convert';

import 'package:flutter_scene_ode_core/src/ode/ode_library_web.dart';

import 'ode_wasm_bytes.g.dart';

Future<void> prepararOde() async {
  debugOdeModuleBytes = (
    glue: utf8.decode(base64.decode(odeGlueBase64)),
    wasm: base64.decode(odeWasmBase64),
  );
}
