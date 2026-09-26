/// La cara web del asignador: `malloc`/`free` del módulo wasm con la forma que
/// tiene `calloc` en `package:ffi`.
///
/// `ode_simulation.dart` reserva sus ocho búferes UNA vez en el constructor y
/// los libera en `dispose`, así que esto no está en ningún camino caliente.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'ffi_shim_web.dart';

/// El asignador que pone a CERO, igual que el de `package:ffi`.
///
/// La puesta a cero no es cosmética: ODE lee campos de `dContact` y `dMass` que
/// el llamante no rellena siempre, y con basura la física sale mal sin dar un
/// error.
const OdeCalloc calloc = OdeCalloc();

/// Sin poner a cero. Está para que la superficie coincida con `package:ffi`;
/// la física no lo usa.
const OdeMalloc malloc = OdeMalloc();

final class OdeCalloc {
  const OdeCalloc();

  Pointer<T> call<T extends NativeType>([int count = 1]) {
    final bytes = sizeOf<T>() * count;
    final p = _malloc(bytes);
    odeHeap.zero(p, bytes);
    return Pointer<T>(p);
  }

  void free(Pointer<NativeType> p) => _free(p.address);
}

final class OdeMalloc {
  const OdeMalloc();

  Pointer<T> call<T extends NativeType>([int count = 1]) =>
      Pointer<T>(_malloc(sizeOf<T>() * count));

  void free(Pointer<NativeType> p) => _free(p.address);
}

int _malloc(int bytes) {
  final p =
      (odeHeap.module.callMethod('_malloc'.toJS, bytes.toJS) as JSNumber)
          .toDartInt;
  if (p == 0) {
    // El módulo se enlaza con ABORTING_MALLOC=1, así que en la práctica esto no
    // debería verse nunca: un OOM aborta ruidosamente antes. Está por si algún
    // día se cambia esa bandera.
    throw StateError('ode.wasm: malloc($bytes) devolvió nulo');
  }
  return p;
}

void _free(int address) {
  if (address == 0) return;
  odeHeap.module.callMethod('_free'.toJS, address.toJS);
}
