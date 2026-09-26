/// LA COSTURA: `dart:ffi` donde lo hay, y una ABI equivalente sobre el heap de
/// wasm donde no.
///
/// `ode_simulation.dart` —las 1488 líneas de física ganadas con sangre— se
/// escribió contra `dart:ffi` y NO se reescribe: solo cambia de dónde vienen
/// `Pointer`, `nullptr`, `sizeOf`, `NativeCallable` y compañía. En nativo esto
/// resuelve a `dart:ffi` de verdad, así que el diff de comportamiento en
/// Android, iOS, macOS y Windows es CERO. En web resuelve al shim.
///
/// Un solo motor de física para las seis plataformas: la alternativa era un
/// segundo `OdeSimulation` para web, y dos copias de esta física divergirían en
/// silencio (las masas en gramos, la banda muerta del servo, los grupos de
/// mecanismo...). Una física distinta en web que nadie vería.
///
/// **La rama por defecto es la WEB a propósito.** El analizador resuelve por
/// ella, así que `flutter analyze` type-chequea la física entera contra la ABI
/// web y cada hueco del shim aparece en el editor, gratis. La rama nativa la
/// prueban los 34 tests del banco de host, que corren en la VM (donde
/// `dart.library.ffi` sí existe).
library;

export 'ffi_shim_web.dart' if (dart.library.ffi) 'ffi_shim_native.dart';
