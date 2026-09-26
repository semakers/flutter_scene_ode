// Cara web del barrel: lo que se exporta donde hay `dart:js_interop` pero no
// `dart:ffi`. Espejo exacto de ode_native.dart — y que exporten lo mismo es lo
// que hace que el consumidor no note en qué rama está.
export 'ode_simulation.dart';
export 'ode_telemetry.dart';
