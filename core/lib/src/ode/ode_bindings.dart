/// Los bindings, en la ABI que toque.
///
/// El fichero que genera ffigen es `ode_bindings_ffi.dart` (no se edita a
/// mano). Su gemelo web, `ode_bindings_web.dart`, ofrece las MISMAS clases con
/// las mismas firmas sobre los exports del módulo wasm, y se genera desde la
/// misma lista de `ffigen.template.yaml` para que no puedan derivar.
library;

export 'ode_bindings_web.dart' if (dart.library.ffi) 'ode_bindings_ffi.dart';
