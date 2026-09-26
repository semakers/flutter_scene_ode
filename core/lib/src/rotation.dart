// Rotación ACTIVA de un vector por un cuaternión.
//
// Existe como archivo aparte por dos razones: no depende de `dart:ffi` (así que
// se puede probar en cualquier plataforma) y es candidato a subir al contrato
// de `scene`, porque la trampa que evita no tiene nada de específico de ODE.
//
// LA TRAMPA, que costó la mitad del spike: `Quaternion.rotate` y
// `Quaternion.rotated` de vector_math aplican `conjugate(q)·v·q`, que es la
// rotación INVERSA. Usarlas para llevar anclas y ejes de local a mundo desplazó
// los pivotes de los hinges hasta 2·|ancla|·sin(θ) en cuanto un cuerpo llegaba
// rotado — el «horn despegado del case» de las capturas. Y no saltaba a la
// vista: el modelo se veía casi bien y el solver no se quejaba, porque
// mantenía sus dos anclas juntas alrededor de un pivote corrido.
//
// `asRotationMatrix()` sí sigue la convención activa, la misma de
// `Matrix4.compose`, que es la que usa el renderer para pintar. Es la de aquí.
//
// Misma familia de error que la luz direccional invertida: una convención de
// signo de una biblioteca que no dice lo que uno cree que dice.
import 'package:vector_math/vector_math.dart';

/// Rota [v] por [q] en sentido ACTIVO (local → mundo).
///
/// No usar `q.rotate(v)` en su lugar: hace lo contrario.
Vector3 rotateActive(Quaternion q, Vector3 v) =>
    q.asRotationMatrix().transform(v.clone());
