# flutter_scene_ode example

Boxes, spheres and cylinders fall onto a floor. flutter_scene draws them and
ODE simulates them: `OdeSimulation` is plugged into flutter_scene's
`PhysicsWorld` component, and every node with a `RigidBody` and a `Collider`
is handled by ODE. Drag sideways to orbit the camera, and press
**Drop more** to add bodies.

```bash
flutter run            # Android, iOS, macOS or Windows
flutter run -d chrome  # web, through ode.wasm
```

It needs Flutter 3.47 or newer, like flutter_scene 0.23.
