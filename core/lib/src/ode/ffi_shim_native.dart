/// La cara nativa de la costura: `dart:ffi` tal cual, sin una capa en medio.
///
/// Que sea un reexport pelado es el punto: en Android, iOS, macOS y Windows
/// `ode_simulation.dart` compila EXACTAMENTE contra lo que compilaba antes de
/// que existiera el soporte de web.
library;

export 'dart:ffi';
