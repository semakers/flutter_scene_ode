/// La carga de la librería, en la plataforma que toque.
///
/// Las dos caras comparten el contrato y, sobre todo, el FALLO BLANDO: nada de
/// esto lanza nunca. Se cachea el motivo y se devuelve null, que es lo que
/// alimenta la pantalla «este dispositivo no puede abrir el constructor».
///
/// La nativa (`ode_library_ffi.dart`) es la de siempre y es el único sitio del
/// paquete con `dart:io`. La web carga el `.wasm` de los assets.
library;

export 'ode_library_web.dart' if (dart.library.ffi) 'ode_library_ffi.dart';
