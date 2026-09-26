/// La cara WEB de la costura: una ABI equivalente a `dart:ffi` sobre el heap
/// lineal del módulo wasm.
///
/// Lo que hay aquí no es una emulación general de `dart:ffi`: es exactamente lo
/// que usa `ode_simulation.dart`, que son siete cosas —`Pointer`, `nullptr`,
/// `sizeOf`, `NativeCallable`, `Void`, `Float` y `DynamicLibrary`— y ni una
/// más. Todo lo que no está es porque la física no lo pide.
///
/// DOS DECISIONES QUE SOSTIENEN EL RESTO
///
/// 1. `Pointer<T>` es un **extension type sobre `int`**: una dirección del heap
///    y nada más, sin objeto que asignar. Los genéricos de Dart son covariantes,
///    así que `nullptr` (un `Pointer<Never>`) se puede pasar donde se espera
///    cualquier `Pointer<T>`, igual que en `dart:ffi`.
/// 2. Los **structs NO son extension types**, son clases-vista normales. Un
///    extension type se BORRA en ejecución (su tipo reificado es el de la
///    representación), así que `sizeOf<dContactGeom>()` vería `T == int` y
///    devolvería basura. Como clases, el `Type` literal funciona y el mapa de
///    tamaños es fiable.
///
/// Los tamaños y desplazamientos NO están escritos aquí: los pregunta
/// `ode_library_web.dart` al mismísimo módulo que se está usando
/// (`nairda_ode_layout`), porque wasm32 es ILP32 y no coincide con el host.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Si esto se compiló con dart2wasm (skwasm) en vez de dart2js.
///
/// **No es un detalle**: `JSFloat32Array.toDart` devuelve una VISTA sin copia en
/// dart2js —los typed lists de dart2js son typed arrays de JS— pero una COPIA
/// en dart2wasm, porque el heap de Dart-wasm no es el de JS. Con la copia, el
/// shim escribiría en un sitio que ODE no lee jamás: la física se quedaría
/// quieta, sin un solo error. Por eso hay dos caminos y una prueba de ida y
/// vuelta al arrancar (ver `ode_library_web.dart`).
const bool kOdeShimIsWasm = bool.fromEnvironment('dart.tool.dart2wasm');

// ---------------------------------------------------------------- el heap

/// El acceso al heap del módulo, que es sobre lo que trabaja todo lo demás.
///
/// Las vistas se cachean UNA vez, y eso es legítimo solo porque el módulo se
/// enlaza con `ALLOW_MEMORY_GROWTH=0`: si la memoria creciera, `HEAPF32` y sus
/// hermanas quedarían DESACOPLADAS del búfer nuevo y toda lectura posterior
/// daría basura o lanzaría. Es una clase entera de heisenbugs comprada por 32 MB
/// fijos, que a ODE le sobran.
final class OdeHeap {
  OdeHeap(this.module)
      : _jsF32 = module.getProperty('HEAPF32'.toJS) as JSFloat32Array,
        _jsI32 = module.getProperty('HEAP32'.toJS) as JSInt32Array,
        _jsU8 = module.getProperty('HEAPU8'.toJS) as JSUint8Array {
    _f32 = kOdeShimIsWasm ? Float32List(0) : _jsF32.toDart;
    _i32 = kOdeShimIsWasm ? Int32List(0) : _jsI32.toDart;
    _u8 = kOdeShimIsWasm ? Uint8List(0) : _jsU8.toDart;
  }

  final JSObject module;
  final JSFloat32Array _jsF32;
  final JSInt32Array _jsI32;
  final JSUint8Array _jsU8;
  late final Float32List _f32;
  late final Int32List _i32;
  late final Uint8List _u8;

  // `kOdeShimIsWasm` es constante de compilación: dart2js elimina la rama
  // muerta entera, así que en el camino que se envía esto es un acceso indexado
  // pelado y no cuesta nada.
  @pragma('dart2js:tryInline')
  double getF32(int addr) => kOdeShimIsWasm
      ? (_jsF32.getProperty((addr >> 2).toJS) as JSNumber).toDartDouble
      : _f32[addr >> 2];

  @pragma('dart2js:tryInline')
  void setF32(int addr, double v) {
    if (kOdeShimIsWasm) {
      _jsF32.setProperty((addr >> 2).toJS, v.toJS);
    } else {
      _f32[addr >> 2] = v;
    }
  }

  @pragma('dart2js:tryInline')
  int getI32(int addr) => kOdeShimIsWasm
      ? (_jsI32.getProperty((addr >> 2).toJS) as JSNumber).toDartInt
      : _i32[addr >> 2];

  @pragma('dart2js:tryInline')
  void setI32(int addr, int v) {
    if (kOdeShimIsWasm) {
      _jsI32.setProperty((addr >> 2).toJS, v.toJS);
    } else {
      _i32[addr >> 2] = v;
    }
  }

  int getU8(int addr) => kOdeShimIsWasm
      ? (_jsU8.getProperty(addr.toJS) as JSNumber).toDartInt
      : _u8[addr];

  void setU8(int addr, int v) {
    if (kOdeShimIsWasm) {
      _jsU8.setProperty(addr.toJS, v.toJS);
    } else {
      _u8[addr] = v;
    }
  }

  /// Pone [n] bytes a cero desde [addr]. Es lo que hace que `calloc` sea
  /// calloc y no malloc: ODE lee campos que el llamante no rellena.
  void zero(int addr, int n) {
    for (var i = 0; i < n; i++) {
      setU8(addr + i, 0);
    }
  }

  /// Copia [n] bytes dentro del propio heap (el `dst.geom = src` del near).
  void copyWithin(int dst, int src, int n) {
    if (dst == src) return;
    for (var i = 0; i < n; i++) {
      setU8(dst + i, getU8(src + i));
    }
  }

  /// Lee una cadena C. Solo se usa para `dGetConfiguration`, así que no hace
  /// falta exportar los ayudantes de string de emscripten.
  String readCString(int addr) {
    final b = <int>[];
    for (var i = addr;; i++) {
      final c = getU8(i);
      if (c == 0) break;
      b.add(c);
    }
    return String.fromCharCodes(b);
  }
}

/// El heap del módulo cargado. Lo fija `ode_library_web.dart` al instanciar.
OdeHeap get odeHeap => _heap!;
OdeHeap? _heap;
set odeHeap(OdeHeap h) => _heap = h;
bool get odeHeapListo => _heap != null;

// ------------------------------------------------------- los tipos marcadores

/// Raíz de la jerarquía, igual que en `dart:ffi`. Nadie instancia nada de esto:
/// son marcadores de TIPO, y su único trabajo es que `Pointer<dxBody>` y
/// `Pointer<dxGeom>` no se puedan confundir.
///
/// Son clases abstractas y no extension types justo por lo mismo que los
/// structs: los structs tienen que poder decir `implements NativeType`, y una
/// clase no puede implementar un extension type.
abstract class NativeType {}

abstract class Void implements NativeType {}
abstract class Float implements NativeType {}
abstract class Double implements NativeType {}
abstract class Int implements NativeType {}
abstract class Int32 implements NativeType {}
abstract class Uint32 implements NativeType {}
abstract class IntPtr implements NativeType {}

/// `const char*`: solo aparece en `dGetConfiguration` y `dCheckConfiguration`.
abstract class Char implements NativeType {}

/// El tipo de una función nativa. En web el «puntero a función» es el índice de
/// la tabla que devuelve `addFunction`.
abstract class NativeFunction<T extends Function> implements NativeType {}

/// Una dirección del heap de wasm, y nada más.
///
/// Los genéricos de Dart son covariantes, así que `Pointer<Never>` —que es lo
/// que es [nullptr]— se puede pasar donde se espera cualquier `Pointer<T>`,
/// igual que en `dart:ffi`.
extension type const Pointer<T extends NativeType>(int address) {
  Pointer<U> cast<U extends NativeType>() => Pointer<U>(address);
}

/// El nulo, con el mismo nombre que en `dart:ffi`. En el heap es la dirección
/// 0, y se compara con `==`, que en un extension type es el de la
/// representación: comparación de enteros.
const Pointer<Never> nullptr = Pointer<Never>(0);

// ------------------------------------------------------------ los tamaños

/// Tamaños de los tipos, en bytes de wasm32. Los rellena
/// `ode_library_web.dart` con lo que dice la sonda del propio módulo: aquí no
/// hay ni un número escrito a mano.
final Map<Type, int> odeSizes = {};

/// El `sizeOf<T>()` de `dart:ffi`.
///
/// Funciona porque los structs son CLASES: si fueran extension types, `T` se
/// borraría a `int` y esto devolvería el tamaño equivocado sin avisar.
int sizeOf<T extends NativeType>() {
  final n = odeSizes[T];
  if (n == null) {
    throw StateError(
      'sizeOf<$T>(): el layout de wasm32 no conoce ese tipo. Lo publica '
      'nairda_ode_layout desde dentro del módulo; si el tipo es nuevo, añádelo '
      'a la X-macro de tool/wasm/nairda_ode_layout.cpp.',
    );
  }
  return n;
}

// --------------------------------------------------------------- los arrays

/// Un array en línea dentro de un struct (`dMass.c`, `dContactGeom.pos`...).
///
/// Es de `dReal`, que es float: todos los que usa la física lo son.
final class Array<T extends NativeType> {
  const Array(this._addr);
  final int _addr;

  double operator [](int i) => odeHeap.getF32(_addr + i * 4);
  void operator []=(int i, double v) => odeHeap.setF32(_addr + i * 4, v);
}

// ------------------------------------------------------------- el callback

/// El equivalente de `NativeCallable.isolateLocal`: mete una función de Dart en
/// la tabla de funciones del módulo y devuelve su índice, que es lo que C ve
/// como puntero a función.
///
/// Es lo que permite que `dSpaceCollide` llame de vuelta a `_near`, o sea que
/// haya contactos. Sin él la física correría sin colisiones y en silencio.
/// Requiere que el módulo se enlace con `ALLOW_TABLE_GROWTH=1`.
///
/// **Solo se admite la firma del near-callback** (`void(ptr, ptr, ptr)` -> la
/// cadena `'viii'` de emscripten), que es la única que usa la física. Emscripten
/// necesita esa cadena y `T` está borrado en ejecución, así que no se puede
/// derivar: mejor un límite explícito que lanza con su nombre que uno implícito
/// que devuelve algo raro.
final class NativeCallable<T extends Function> {
  NativeCallable.isolateLocal(Function fn) {
    // Tras el borrado, los `Pointer` son `int`: la función declarada
    // `void Function(Pointer<Void>, Pointer<dxGeom>, Pointer<dxGeom>)` es en
    // ejecución `void Function(int, int, int)`.
    final void Function(int, int, int) dart;
    try {
      dart = fn as void Function(int, int, int);
    } on TypeError {
      throw UnsupportedError(
        'NativeCallable en web: solo está implementada la firma del '
        'near-callback de dSpaceCollide, void(Pointer, Pointer, Pointer). '
        'Si hace falta otra, hay que añadir su cadena de firma de emscripten '
        'en ffi_shim_web.dart.',
      );
    }
    final js = ((JSNumber a, JSNumber b, JSNumber c) {
      dart(a.toDartInt, b.toDartInt, c.toDartInt);
    }).toJS;
    _index = (odeHeap.module.callMethod('addFunction'.toJS, js, 'viii'.toJS)
            as JSNumber)
        .toDartInt;
  }

  late final int _index;

  Pointer<NativeFunction<T>> get nativeFunction =>
      Pointer<NativeFunction<T>>(_index);

  void close() {
    odeHeap.module.callMethod('removeFunction'.toJS, _index.toJS);
  }
}

// ---------------------------------------------------------- la «librería»

/// El equivalente de `DynamicLibrary`: en web no se abre nada, se instancia un
/// módulo. Existe para que `OdeBindings(lib)` tenga la misma forma en las dos
/// ramas.
final class DynamicLibrary {
  const DynamicLibrary(this.module);
  final JSObject module;
}

// --------------------------------------------- indexar punteros a escalares

/// `p[0]`, `p[1]`... sobre un `Pointer<dReal>`.
///
/// `dReal` es `Float` (precisión SIMPLE, no negociable: los bindings lo tienen
/// clavado y un módulo en doble precisión no daría error, leería basura), así
/// que un elemento son 4 bytes.
extension PointerFloat on Pointer<Float> {
  double operator [](int i) => odeHeap.getF32(address + i * 4);
  void operator []=(int i, double v) => odeHeap.setF32(address + i * 4, v);
}

extension PointerInt on Pointer<Int> {
  int operator [](int i) => odeHeap.getI32(address + i * 4);
  void operator []=(int i, int v) => odeHeap.setI32(address + i * 4, v);
}
