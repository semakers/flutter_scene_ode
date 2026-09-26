/// El asignador, en su propio fichero porque `ode_simulation.dart` lo importa
/// SIN prefijo (`calloc<dContactGeom>(8)`, no `ffi.calloc<...>`). Meterlo en
/// ffi_shim.dart obligaría a tocar los diecisiete sitios que lo usan, que es
/// justo lo que esta costura existe para no hacer.
library;

export 'ffi_alloc_web.dart' if (dart.library.ffi) 'ffi_alloc_native.dart';
