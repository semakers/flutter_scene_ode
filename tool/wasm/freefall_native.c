/* El gemelo NATIVO de freefall.mjs: el mismo escenario, la misma configuración
 * del mundo, los mismos tres tramos.
 *
 * Existe para responder a una sola pregunta, y responderla ANTES de escribir
 * una línea de Dart: ¿la física que corre dentro de wasm es la misma que la que
 * llevamos verificada en cuatro plataformas? Si los dos dan el mismo reposo, el
 * mismo hundimiento y los mismos contactos, el port es fiel; si no, se sabe
 * aquí y no dentro del navegador con veinte capas encima.
 *
 * Compilar y correr:  tool/wasm/paridad.sh
 */
#include <math.h>
#include <stdio.h>

#include <ode/ode.h>

static dWorldID world;
static dJointGroupID group;
static dGeomID geoms_space;

#define MAX_CONTACTS 8
static dContactGeom g_geoms[MAX_CONTACTS];
static dContact g_contact;
static int g_llamado = 0, g_contactos = 0;
static dReal g_pen_max = 0;

static void nearCallback(void *data, dGeomID o1, dGeomID o2) {
  (void)data;
  g_llamado++;
  int n = dCollide(o1, o2, MAX_CONTACTS, g_geoms, sizeof(dContactGeom));
  if (n == 0) return;
  g_contactos += n;
  for (int i = 0; i < n; i++) {
    if (g_geoms[i].depth > g_pen_max) g_pen_max = g_geoms[i].depth;
    g_contact.surface.mode = dContactApprox1 | dContactSoftCFM;
    g_contact.surface.mu = REAL(0.8);
    g_contact.surface.soft_cfm = REAL(1e-4);
    g_contact.geom = g_geoms[i];
    dJointID j = dJointCreateContact(world, group, &g_contact);
    dJointAttach(j, dGeomGetBody(o1), dGeomGetBody(o2));
  }
}

int main(void) {
  dInitODE2(0);
  world = dWorldCreate();
  dSpaceID space = dHashSpaceCreate(0);
  group = dJointGroupCreate(0);
  (void)geoms_space;

  dWorldSetGravity(world, 0, REAL(-9.81), 0);
  dWorldSetCFM(world, REAL(1e-5));
  dWorldSetERP(world, REAL(0.2));
  dWorldSetQuickStepNumIterations(world, 40);
  dWorldSetContactSurfaceLayer(world, REAL(0.001));
  dWorldSetContactMaxCorrectingVel(world, REAL(1.0));
  dWorldSetAutoDisableFlag(world, 1);
  dWorldSetAutoDisableLinearThreshold(world, REAL(0.08));
  dWorldSetAutoDisableAngularThreshold(world, REAL(0.08));

  dCreatePlane(space, 0, 1, 0, 0);

  const dReal R = REAL(1.0);
  dBodyID body = dBodyCreate(world);
  dMass m;
  dMassSetSphereTotal(&m, REAL(100.0), R);
  dBodySetMass(body, &m);
  dGeomID geom = dCreateSphere(space, R);
  dGeomSetBody(geom, body);
  dBodySetPosition(body, 0, REAL(10.0), 0);

  const dReal DT = REAL(1.0) / REAL(240.0);
  dReal y0 = dBodyGetPosition(body)[1];

  for (int tramo = 0; tramo < 3; tramo++) {
    int pasos = (tramo == 2) ? 120 : 360;   /* 0.5 s : 1.5 s, a 240 Hz */
    g_pen_max = 0;
    for (int i = 0; i < pasos; i++) {
      dSpaceCollide(space, 0, &nearCallback);
      dWorldQuickStep(world, DT);
      dJointGroupEmpty(group);
    }
    if (tramo == 0) printf("pen_impacto %.6f\n", (double)g_pen_max);
  }

  dReal y1 = dBodyGetPosition(body)[1];
  dReal vy = dBodyGetLinearVel(body)[1];

  /* Formato plano clave=valor: lo lee paridad.sh y lo compara con el de node
   * sin tener que parsear prosa. */
  printf("y0 %.6f\n", (double)y0);
  printf("y_final %.6f\n", (double)y1);
  printf("vy %.6f\n", (double)fabs((double)vy));
  printf("pen_reposo %.6f\n", (double)g_pen_max);
  printf("hundimiento %.6f\n", (double)(R - y1));
  printf("dormida %d\n", dBodyIsEnabled(body) == 0);
  printf("near_llamado %d\n", g_llamado);
  printf("contactos %d\n", g_contactos);

  dJointGroupDestroy(group);
  dSpaceDestroy(space);
  dWorldDestroy(world);
  dCloseODE();
  return 0;
}
