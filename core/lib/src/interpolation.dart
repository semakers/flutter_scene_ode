// Interpolación de poses entre dos pasos de física.
//
// Sin `dart:ffi` a propósito: no tiene nada de ODE y es candidato a subir al
// contrato de `scene`, donde cualquier backend con paso fijo necesita lo mismo.
import 'package:vector_math/vector_math.dart';

/// nlerp con arco corto.
///
/// Basta a 240 Hz: los pasos son diminutos y la diferencia con un slerp de
/// verdad no se ve. Lo que sí importa es el volteo de signo: sin él, dos
/// cuaterniones que representan la misma rotación por caminos opuestos
/// producen un latigazo de casi una vuelta entera al interpolar.
Quaternion nlerpShortest(Quaternion a, Quaternion b, double t) {
  final dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
  var bx = b.x, by = b.y, bz = b.z, bw = b.w;
  if (dot < 0) {
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
  }
  return Quaternion(
    a.x + (bx - a.x) * t,
    a.y + (by - a.y) * t,
    a.z + (bz - a.z) * t,
    a.w + (bw - a.w) * t,
  )..normalize();
}

/// Interpolación lineal de posición entre la pose previa y la actual.
Vector3 lerpPosition(Vector3 prev, Vector3 curr, double t) =>
    prev + (curr - prev).scaled(t);
