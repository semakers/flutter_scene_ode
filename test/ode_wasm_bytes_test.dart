// Que los tres artefactos derivados del .wasm sigan siendo del MISMO .wasm.
//
// Hay tres copias del módulo en el repo, y cada una existe por una razón:
//   - assets/ode.{js,wasm}         lo que se envía y carga la app
//   - test/ode_wasm_bytes.g.dart   lo que corre el banco de navegador
//   - tool/ode_wasm_layout.json    los desplazamientos con los que se generaron
//                                  los bindings web
//
// Si una se queda atrás, el fallo NO es un error de compilación: es un banco
// que da verde contra un módulo viejo, o unos campos leídos corridos. Por eso
// se cotejan aquí, desde la VM, donde sí hay dart:io.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../core/test/ode_wasm_bytes.g.dart';

void main() {
  test('los bytes del banco de navegador son los de assets/ode.wasm', () {
    final enDisco = File('assets/ode.wasm').readAsBytesSync();
    final enElBanco = base64.decode(odeWasmBase64);
    expect(
      enElBanco,
      orderedEquals(enDisco),
      reason: 'test/ode_wasm_bytes.g.dart está rancio. Corre tool/vendor_wasm.sh.',
    );
  });

  test('el glue del banco de navegador es el de assets/ode.js', () {
    final enDisco = File('assets/ode.js').readAsStringSync();
    expect(
      utf8.decode(base64.decode(odeGlueBase64)),
      enDisco,
      reason: 'test/ode_wasm_bytes.g.dart está rancio. Corre tool/vendor_wasm.sh.',
    );
  });

  test('los bindings web se generaron con el layout que hay commiteado', () {
    // No se compara contra el módulo (eso lo hace el cargador al arrancar, que
    // es donde de verdad importa): se comprueba que el generador no se quedó a
    // medias, o sea que el JSON y el .dart hablan del mismo layout.
    final json = jsonDecode(File('tool/ode_wasm_layout.json').readAsStringSync())
        as Map<String, dynamic>;
    final generado = File('core/lib/src/ode/ode_bindings_web.dart').readAsStringSync();
    for (final e in json.entries) {
      expect(
        generado,
        contains("'${e.key}': ${e.value},"),
        reason: 'ode_bindings_web.dart no lleva ${e.key}. '
            'Corre dart tool/gen_bindings_web.dart.',
      );
    }
    // wasm32 es ILP32: si esto cambiara, TODOS los desplazamientos cambian.
    expect(json['sizeof.pointer'], 4);
    expect(json['sizeof.dReal'], 4, reason: 'precisión simple, no negociable');
  });

  test('ode_bindings_web.dart está al día respecto al generador', () {
    // El generador es determinista y su `--check` no escribe nada: si alguien
    // toca ffigen.template.yaml o regenera los bindings de ffigen y se olvida
    // del gemelo, las dos ramas empiezan a hablar de funciones distintas — y
    // eso no da error de compilación en ninguna plataforma.
    final r = Process.runSync(
      '${Platform.environment['HOME']}/dev/dart-arm64/bin/dart',
      ['tool/gen_bindings_web.dart', '--check'],
    );
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, skip: !File('${Platform.environment['HOME']}/dev/dart-arm64/bin/dart')
      .existsSync());

  test('el .wasm que se envía es un módulo de verdad y pesa lo que debe', () {
    final w = File('assets/ode.wasm').readAsBytesSync();
    expect(w.sublist(0, 4), [0x00, 0x61, 0x73, 0x6d], reason: 'la firma \\0asm');
    // Un .wasm de 20 KB sería ODE sin ODE dentro.
    expect(w.length, greaterThan(80 * 1024));
  });
}
