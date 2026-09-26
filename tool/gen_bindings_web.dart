// Genera core/lib/src/ode/ode_bindings_web.dart: el gemelo web de los bindings de
// ffigen.
//
// POR QUÉ SE GENERA Y NO SE ESCRIBE A MANO
// ----------------------------------------
// Son 84 funciones. Dos listas escritas a mano derivarían, y la deriva aquí no
// da un error de compilación: da una función que en web hace otra cosa. Así
// que la fuente es la MISMA que la de ffigen —`ffigen.template.yaml` para qué
// funciones, y el propio `ode_bindings_ffi.dart` para sus firmas— y los
// tamaños salen de `tool/ode_wasm_layout.json`, que lo publica la sonda desde
// dentro del módulo.
//
// Uso:
//   dart tool/gen_bindings_web.dart            # escribe
//   dart tool/gen_bindings_web.dart --check    # falla si está desactualizado
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final raiz = File.fromUri(Platform.script).parent.parent.path;
  final ffi = File('$raiz/core/lib/src/ode/ode_bindings_ffi.dart').readAsStringSync();
  final plantilla = File('$raiz/ffigen.template.yaml').readAsStringSync();
  final layout = (json.decode(
    File('$raiz/tool/ode_wasm_layout.json').readAsStringSync(),
  ) as Map).cast<String, int>();

  final funciones = _funcionesDeLaPlantilla(plantilla);
  if (funciones.length < 80) {
    stderr.writeln('solo ${funciones.length} funciones: ¿cambió el formato de '
        'ffigen.template.yaml?');
    exit(1);
  }

  final salida = _generar(ffi, funciones, layout);
  final destino = File('$raiz/core/lib/src/ode/ode_bindings_web.dart');

  if (args.contains('--check')) {
    final actual = destino.existsSync() ? destino.readAsStringSync() : '';
    if (actual != salida) {
      stderr.writeln('ode_bindings_web.dart está desactualizado.');
      stderr.writeln('Corre: dart tool/gen_bindings_web.dart');
      exit(1);
    }
    stdout.writeln('ode_bindings_web.dart al día (${funciones.length} funciones).');
    return;
  }
  destino.writeAsStringSync(salida);
  stdout.writeln('${destino.path}: ${funciones.length} funciones.');
}

/// La MISMA extracción que hacen tool/build_vendored_host.sh y
/// tool/build_ode_wasm.sh, para que las tres listas sean la misma lista.
List<String> _funcionesDeLaPlantilla(String yaml) {
  final lineas = yaml.split('\n');
  final desde = lineas.indexWhere((l) => l.startsWith('functions:'));
  final hasta = lineas.indexWhere((l) => l.startsWith('structs:'));
  final re = RegExp(r'^\s*- ([A-Za-z_][A-Za-z0-9_]*)\s*$');
  return [
    for (final l in lineas.sublist(desde + 1, hasta))
      if (re.firstMatch(l) case final m?) m.group(1)!,
  ];
}

class _Param {
  _Param(this.tipo, this.nombre);
  final String tipo; // ya traducido a la ABI web
  final String nombre;
  bool get esPuntero => tipo.startsWith('Pointer<');
}

class _Funcion {
  _Funcion(this.nombre, this.retorno, this.params);
  final String nombre;
  final String retorno;
  final List<_Param> params;
}

/// Saca la declaración pública de [nombre] del fichero de ffigen.
///
/// Todas tienen la misma forma:
///   `  <retorno> <nombre>(<params>) {\n    return _<nombre>(...);`
_Funcion? _declaracion(String ffi, String nombre) {
  final re = RegExp(r'\n  ([\w.<>, ]+?) ' + RegExp.escape(nombre) + r'\(');
  final m = re.firstMatch(ffi);
  if (m == null) return null;
  // Equilibra paréntesis desde la apertura para coger la lista de parámetros
  // entera, que puede venir en varias líneas.
  var i = m.end - 1, prof = 0, fin = -1;
  for (; i < ffi.length; i++) {
    if (ffi[i] == '(') prof++;
    if (ffi[i] == ')') {
      prof--;
      if (prof == 0) { fin = i; break; }
    }
  }
  if (fin < 0) return null;
  // Y confirma que es la definición, no una declaración de puntero.
  if (!RegExp(r'^\s*\{').hasMatch(ffi.substring(fin + 1, fin + 4))) return null;

  final crudo = ffi.substring(m.end, fin);
  final params = <_Param>[];
  for (final p in _partirPorComasDeNivel0(crudo)) {
    final t = p.trim();
    if (t.isEmpty) continue;
    final corte = t.lastIndexOf(' ');
    params.add(_Param(_tipoWeb(t.substring(0, corte).trim()), t.substring(corte + 1)));
  }
  return _Funcion(nombre, _tipoWeb(m.group(1)!.trim()), params);
}

List<String> _partirPorComasDeNivel0(String s) {
  final out = <String>[];
  var prof = 0, ini = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '<' || c == '(') prof++;
    if (c == '>' || c == ')') prof--;
    if (c == ',' && prof == 0) { out.add(s.substring(ini, i)); ini = i + 1; }
  }
  out.add(s.substring(ini));
  return out;
}

/// `ffi.Pointer<ffi.Void>` -> `Pointer<Void>`. Los tipos de Dart puros
/// (`int`, `double`, `void`) pasan tal cual.
String _tipoWeb(String t) => t.replaceAll('ffi.', '');

String _generar(String ffi, List<String> funciones, Map<String, int> layout) {
  final b = StringBuffer();
  b.writeln('''
// GENERADO por tool/gen_bindings_web.dart. No editar a mano.
//
// El gemelo web de ode_bindings_ffi.dart: las MISMAS clases con las mismas
// firmas, sobre los exports del módulo wasm en vez de sobre símbolos de una
// librería dinámica. Las firmas se copian del fichero de ffigen y la lista de
// funciones sale de ffigen.template.yaml, así que las dos ramas no pueden
// derivar sin que alguien se entere.
//
// Los desplazamientos y tamaños son los de wasm32 (ILP32), MEDIDOS por
// tool/wasm/nairda_ode_layout.cpp desde dentro del propio módulo y volcados a
// tool/ode_wasm_layout.json. No hay ni un número supuesto: el cargador vuelve a
// preguntárselos al módulo que carga y aborta si no cuadran.
//
// ignore_for_file: non_constant_identifier_names, camel_case_types
// ignore_for_file: constant_identifier_names
// ignore_for_file: library_private_types_in_public_api
library;

import 'dart:js_interop';

import 'ffi_shim_web.dart';

export 'ffi_shim_web.dart' show DynamicLibrary;
''');

  // --- los tipos opacos (dxWorld, dxBody...): solo marcadores para que
  //     `Pointer<dxBody>` y `Pointer<dxGeom>` sean tipos distintos.
  final opacos = RegExp(r'^final class (\w+) extends ffi\.Opaque \{\}',
          multiLine: true)
      .allMatches(ffi)
      .map((m) => m.group(1)!)
      .where((n) => n.startsWith('dx'))
      .toList();
  b.writeln('// Tipos opacos: nunca se desreferencian, solo viajan como '
      'direcciones.\n// Que sean tipos DISTINTOS es lo que impide pasar un '
      'cuerpo donde va un geom.');
  for (final o in opacos) {
    b.writeln('abstract class $o implements NativeType {}');
  }
  b.writeln();

  // --- typedefs
  b.writeln('''
/// Precisión SIMPLE, igual que en la rama nativa. Si esto fuera `Double` el
/// módulo no daría error de enlace: leería basura.
typedef dReal = Float;
typedef DartdReal = double;
typedef dNearCallback
    = NativeFunction<Void Function(Pointer<Void>, Pointer<dxGeom>, Pointer<dxGeom>)>;
''');

  // --- las constantes y los enums, que son enteros y no dependen de la ABI:
  //     se copian tal cual del fichero de ffigen.
  final consts = RegExp(r'^const int (\w+) = (-?\d+);', multiLine: true)
      .allMatches(ffi);
  b.writeln('// Constantes copiadas de los bindings de ffigen: son enteros y no '
      'dependen\n// de la ABI, así que aquí valen lo mismo.');
  for (final m in consts) {
    b.writeln('const int ${m.group(1)} = ${m.group(2)};');
  }
  b.writeln();
  for (final m in RegExp(r'^enum (\w+) \{\n(.*?)^\}', multiLine: true, dotAll: true)
      .allMatches(ffi)) {
    final nombre = m.group(1)!;
    if (!nombre.startsWith('d')) continue; // los de glibc no hacen falta
    final cuerpo = m.group(2)!
        .split('\n')
        .where((l) => RegExp(r'^\s*\w+\(-?\d+\)').hasMatch(l))
        .map((l) => '  ${_sinFinal(l.trim())}')
        .join(',\n');
    b.writeln('enum $nombre {\n$cuerpo;\n\n  const $nombre(this.value);\n'
        '  final int value;\n}\n');
  }

  // --- los structs, como CLASES-VISTA (no extension types: se borrarían y
  //     sizeOf<T>() vería `int`).
  b.write(_structs(layout));

  // --- el módulo: cada export como miembro `external`, que dart2js compila a
  //     una llamada directa a la propiedad. Es el camino caliente.
  b.writeln('''
/// Los exports del módulo wasm, como miembros `external`.
///
/// Con `dart:js_interop` esto compila a `modulo._dBodyGetPosition(b)` pelado,
/// sin buscar propiedades por cadena en cada llamada: importa, porque el paso
/// de física llama aquí miles de veces por segundo.
///
/// Los punteros son `int` a este nivel: la dirección del heap y nada más.
@JS()
extension type _Exports._(JSObject _) implements JSObject {''');
  final decls = <_Funcion>[];
  for (final f in funciones) {
    final d = _declaracion(ffi, f);
    if (d == null) {
      stderr.writeln('no encontré la declaración de $f en ode_bindings_ffi.dart');
      exit(1);
    }
    decls.add(d);
    final ps = d.params
        .map((p) => '${p.esPuntero || p.tipo == 'int' ? 'int' : p.tipo} ${p.nombre}')
        .join(', ');
    final ret = d.retorno.startsWith('Pointer<') ? 'int' : d.retorno;
    b.writeln("  @JS('_$f')\n  external $ret $f($ps);");
  }
  for (final extra in ['nairda_ode_layout_count', 'nairda_ode_configuration']) {
    b.writeln("  @JS('_$extra')\n  external int $extra();");
  }
  b.writeln("  @JS('_nairda_ode_layout')\n  external int nairda_ode_layout(int out, int cap);");
  b.writeln("  @JS('_nairda_ode_layout_names')\n  external int nairda_ode_layout_names();");
  b.writeln('}\n');

  // --- la clase pública, con las firmas tipadas de la rama nativa.
  b.writeln('''
/// La misma superficie que la `OdeBindings` de ffigen, para que
/// `ode_simulation.dart` no note la diferencia.
class OdeBindings {
  OdeBindings(DynamicLibrary lib) : _m = _Exports._(lib.module);

  final _Exports _m;
''');
  for (final d in decls) {
    final ps = d.params.map((p) => '${p.tipo} ${p.nombre}').join(', ');
    final args = d.params
        .map((p) => p.esPuntero ? '${p.nombre}.address' : p.nombre)
        .join(', ');
    final llamada = '_m.${d.nombre}($args)';
    final cuerpo = d.retorno == 'void'
        ? llamada
        : d.retorno.startsWith('Pointer<')
            ? '${d.retorno}($llamada)'
            : llamada;
    b.writeln('  ${d.retorno} ${d.nombre}($ps) => $cuerpo;\n');
  }
  b.writeln('}');
  return b.toString();
}

/// Las cuatro vistas de struct, con los desplazamientos medidos.
String _structs(Map<String, int> L) {
  int o(String k) => L[k] ?? (throw StateError('falta $k en ode_wasm_layout.json'));
  final b = StringBuffer();
  b.writeln('''
// Los structs son CLASES, no extension types, y eso NO es un detalle de estilo:
// un extension type se borra en ejecución (su tipo reificado es el de la
// representación), así que `sizeOf<dContactGeom>()` vería `T == int` y
// devolvería el tamaño equivocado sin dar ningún error.

/// Parámetros de superficie del contacto. Vista sobre `dirección + campo`.
class dSurfaceParameters implements NativeType {
  dSurfaceParameters(this._a);
  final int _a;
''');
  for (final campo in ['mode']) {
    b.writeln('  int get $campo => odeHeap.getI32(_a + ${o('dSurfaceParameters.$campo')});');
    b.writeln('  set $campo(int v) => odeHeap.setI32(_a + ${o('dSurfaceParameters.$campo')}, v);');
  }
  for (final campo in [
    'mu', 'mu2', 'rho', 'rho2', 'rhoN', 'bounce', 'bounce_vel',
    'soft_erp', 'soft_cfm', 'motion1', 'motion2', 'motionN', 'slip1', 'slip2',
  ]) {
    b.writeln('  double get $campo => odeHeap.getF32(_a + ${o('dSurfaceParameters.$campo')});');
    b.writeln('  set $campo(double v) => odeHeap.setF32(_a + ${o('dSurfaceParameters.$campo')}, v);');
  }
  b.writeln('}\n');

  b.writeln('''
/// Un punto de contacto entre dos geoms.
class dContactGeom implements NativeType {
  dContactGeom(this._a);
  final int _a;

  Array<dReal> get pos => Array<dReal>(_a + ${o('dContactGeom.pos')});
  Array<dReal> get normal => Array<dReal>(_a + ${o('dContactGeom.normal')});
  double get depth => odeHeap.getF32(_a + ${o('dContactGeom.depth')});
  set depth(double v) => odeHeap.setF32(_a + ${o('dContactGeom.depth')}, v);
  Pointer<dxGeom> get g1 => Pointer<dxGeom>(odeHeap.getI32(_a + ${o('dContactGeom.g1')}));
  set g1(Pointer<dxGeom> v) => odeHeap.setI32(_a + ${o('dContactGeom.g1')}, v.address);
  Pointer<dxGeom> get g2 => Pointer<dxGeom>(odeHeap.getI32(_a + ${o('dContactGeom.g2')}));
  set g2(Pointer<dxGeom> v) => odeHeap.setI32(_a + ${o('dContactGeom.g2')}, v.address);
  int get side1 => odeHeap.getI32(_a + ${o('dContactGeom.side1')});
  int get side2 => odeHeap.getI32(_a + ${o('dContactGeom.side2')});
}

/// El contacto entero, tal como lo pide `dJointCreateContact`.
class dContact implements NativeType {
  dContact(this._a);
  final int _a;

  dSurfaceParameters get surface => dSurfaceParameters(_a + ${o('dContact.surface')});
  dContactGeom get geom => dContactGeom(_a + ${o('dContact.geom')});
  Array<dReal> get fdir1 => Array<dReal>(_a + ${o('dContact.fdir1')});
}

/// La masa y el tensor de inercia.
class dMass implements NativeType {
  dMass(this._a);
  final int _a;

  double get mass => odeHeap.getF32(_a + ${o('dMass.mass')});
  set mass(double v) => odeHeap.setF32(_a + ${o('dMass.mass')}, v);
  Array<dReal> get c => Array<dReal>(_a + ${o('dMass.c')});
  Array<dReal> get I => Array<dReal>(_a + ${o('dMass.I')});
}

// `.ref` y `p[i]` sobre punteros a struct. En `dart:ffi` esto es magia del
// compilador; aquí hace falta una extensión por tipo, que es barato porque los
// structs son exactamente cuatro.
extension DSurfaceParametersPointer on Pointer<dSurfaceParameters> {
  dSurfaceParameters get ref => dSurfaceParameters(address);
}

extension DContactGeomPointer on Pointer<dContactGeom> {
  dContactGeom get ref => dContactGeom(address);
  dContactGeom operator [](int i) =>
      dContactGeom(address + i * ${o('sizeof.dContactGeom')});
}

extension DContactPointer on Pointer<dContact> {
  dContact get ref => dContact(address);
  dContact operator [](int i) => dContact(address + i * ${o('sizeof.dContact')});
}

extension DMassPointer on Pointer<dMass> {
  dMass get ref => dMass(address);
  dMass operator [](int i) => dMass(address + i * ${o('sizeof.dMass')});
}

/// El layout ENTERO con el que se generó este fichero.
///
/// El cargador se lo vuelve a preguntar al módulo que carga y aborta si no
/// cuadra: así «el ode.wasm de assets/ es de hace tres semanas» se nota al
/// arrancar y no como una física que se mueve raro.
const Map<String, int> odeGeneratedLayout = {
@@LAYOUT@@};

/// Los tamaños que necesita `sizeOf<T>()`. Van aquí, y no escritos a mano en el
/// shim, porque salen del mismo JSON que los desplazamientos.
final Map<Type, int> odeStructSizes = {
  dMass: ${o('sizeof.dMass')},
  dContact: ${o('sizeof.dContact')},
  dContactGeom: ${o('sizeof.dContactGeom')},
  dSurfaceParameters: ${o('sizeof.dSurfaceParameters')},
  Float: ${o('sizeof.dReal')},
  Int: ${o('sizeof.int')},
};
''');
  final entradas = (L.keys.toList()..sort())
      .map((k) => "  '$k': ${L[k]},")
      .join('\n');
  return b.toString().replaceFirst('@@LAYOUT@@', '$entradas\n');
}

/// Quita la coma o el punto y coma final de una entrada de enum: la última del
/// bloque original ya trae el suyo, y volver a añadirlo da `dSA__MAX(3);;`.
String _sinFinal(String s) {
  var r = s;
  while (r.endsWith(',') || r.endsWith(';')) {
    r = r.substring(0, r.length - 1);
  }
  return r;
}
