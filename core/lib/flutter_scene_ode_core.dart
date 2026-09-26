/// El backend de física ODE para el contrato `PhysicsSimulation` de
/// `package:scene`, sin Flutter.
///
/// Es lo que era `lib/src/` del plugin `flutter_scene_ode` hasta el 2026-09-17,
/// movido aquí tal cual para que el evaluador de concursos —un binario de
/// `dart compile exe`, sin pantalla— pueda correr la MISMA física que el
/// teléfono. El plugin lo re-exporta: nadie que importe `flutter_scene_ode` nota nada.
library;

// El export condicional NO es una mejora, es obligatorio: `dart:ffi` no existe
// en web y en cuanto la app dependa de este paquete, `flutter build web`
// moriría con un error de dart2js que ni menciona a ODE. El bucle de desarrollo
// diario de Nairda es solo-web, así que ese fallo llegaría justo donde más
// molesta. Mismo patrón que `nairda_compiler.dart`.
//
// En web se exporta el stub: misma superficie pública, `isAvailable == false` y
// un motivo legible — que es exactamente lo que alimenta la pantalla «este
// dispositivo no puede abrir el constructor».
export 'src/ode_unsupported.dart'
    if (dart.library.ffi) 'src/ode/ode_native.dart'
    if (dart.library.js_interop) 'src/ode/ode_web.dart';
