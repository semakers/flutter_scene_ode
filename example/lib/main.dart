// flutter_scene_ode example: a rain of boxes, spheres and cylinders.
//
// flutter_scene owns the scene graph and the rendering. ODE owns the physics:
// OdeSimulation goes into flutter_scene's PhysicsWorld component, and every
// node with a RigidBody and a Collider is simulated by ODE.
//
// Remember the backend's units: 1 unit is about 1 cm and masses are grams.
import 'dart:math' as math;

import 'package:flutter/material.dart' hide BoxShape, Material;
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_ode/flutter_scene_ode.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OdeRainPage(),
    ));

class OdeRainPage extends StatefulWidget {
  const OdeRainPage({super.key});

  @override
  State<OdeRainPage> createState() => _OdeRainPageState();
}

class _OdeRainPageState extends State<OdeRainPage> {
  Scene? _scene;
  String? _error;
  int _dropped = 0;
  final _random = math.Random(7);
  double _orbit = 0.6;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // On the web this downloads ode.wasm; natively it returns at once.
    await FlutterSceneOde.ensureAvailable();
    if (!OdeSimulation.isAvailable) {
      setState(() => _error = OdeSimulation.unavailableReason);
      return;
    }
    await Scene.initializeStaticResources();

    final scene = Scene()
      ..environment = EnvironmentMap.constantDiffuse(vm.Vector3.all(0.6));
    scene.add(Node(name: 'sun')
      ..addComponent(DirectionalLightComponent(DirectionalLight(
        direction: vm.Vector3(0.4, 1.0, 0.3),
        color: vm.Vector3.all(0.9),
        intensity: 3.0,
      ))));

    // The physics world: ODE behind flutter_scene's PhysicsWorld.
    scene.root.addComponent(PhysicsWorld(OdeSimulation()));

    // The floor: a fixed box whose top face is at y = 0.
    scene.add(Node(
      name: 'floor',
      localTransform: vm.Matrix4.translation(vm.Vector3(0, -0.5, 0)),
    )
      ..mesh = Mesh(CuboidGeometry(vm.Vector3(30, 1, 30)), _matte(0.8, 0.8, 0.78))
      ..addComponent(RigidBody(type: BodyType.fixed))
      ..addComponent(
          Collider(shape: BoxShape(halfExtents: vm.Vector3(15, 0.5, 15)))));

    setState(() => _scene = scene);
    for (var i = 0; i < 24; i++) {
      _drop();
    }
  }

  static PhysicallyBasedMaterial _matte(double r, double g, double b) =>
      PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(r, g, b, 1)
        ..metallicFactor = 0
        ..roughnessFactor = 0.7;

  /// Drops one random body from above the floor.
  void _drop() {
    final scene = _scene;
    if (scene == null) return;
    final kind = _dropped % 3;
    final color = HSVColor.fromAHSV(1, (_dropped * 47) % 360, 0.6, 0.9).toColor();
    final material = _matte(color.r, color.g, color.b);
    final at = vm.Vector3(
      (_random.nextDouble() - 0.5) * 6,
      6 + _dropped % 8 * 1.5,
      (_random.nextDouble() - 0.5) * 6,
    );
    final spin = vm.Quaternion.axisAngle(
        vm.Vector3(_random.nextDouble(), 1, _random.nextDouble()).normalized(),
        _random.nextDouble() * math.pi);

    final (Shape shape, MeshGeometry geometry) = switch (kind) {
      0 => (
          BoxShape(halfExtents: vm.Vector3(0.5, 0.5, 0.5)),
          CuboidGeometry(vm.Vector3.all(1)),
        ),
      1 => (SphereShape(radius: 0.5), SphereGeometry(radius: 0.5)),
      _ => (
          CylinderShape(radius: 0.4, halfHeight: 0.5),
          CylinderGeometry(bottomRadius: 0.4, topRadius: 0.4, height: 1),
        ),
    };

    scene.add(Node(
      name: 'body$_dropped',
      localTransform: vm.Matrix4.compose(at, spin, vm.Vector3.all(1)),
    )
      ..mesh = Mesh(geometry, material)
      ..addComponent(RigidBody())
      ..addComponent(Collider(
          shape: shape, material: PhysicsMaterial(friction: 0.6))));
    _dropped++;
  }

  Camera _camera(Duration elapsed) {
    final eye = vm.Vector3(math.sin(_orbit) * 16, 9, math.cos(_orbit) * 16);
    return PerspectiveCamera(position: eye, target: vm.Vector3(0, 1, 0));
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    return Scaffold(
      backgroundColor: const Color(0xFF1B2430),
      body: Stack(children: [
        if (scene != null)
          Positioned.fill(
            child: GestureDetector(
              onHorizontalDragUpdate: (d) =>
                  setState(() => _orbit -= d.delta.dx * 0.01),
              child: SceneView(scene, cameraBuilder: _camera),
            ),
          )
        else
          Center(
            child: Text(
              _error ?? 'Loading ODE…',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        Positioned(
          left: 16,
          top: 16,
          child: Text(
            'flutter_scene + ODE · $_dropped bodies',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ]),
      floatingActionButton: scene == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() {
                for (var i = 0; i < 6; i++) {
                  _drop();
                }
              }),
              icon: const Icon(Icons.add),
              label: const Text('Drop more'),
            ),
    );
  }
}
