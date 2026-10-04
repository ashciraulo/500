"""Preview renders for review (Cycles, CPU). Not part of the game assets."""
import math

import bpy

from . import common as C


def _ground(color="#8a8780", size=40):
    g = C.box("PreviewGround", (size, size, 0.02), (0, 0, -0.01), C.mat("PreviewGround", color, rough=0.9))
    return g


def car(prefix, spec, cockpit=True, res=(960, 540), samples=32):
    C.render_setup(res, samples, world="#c9d6e0", strength=0.8)
    _ground()
    C.sun(rot=(48, 10, 140), energy=3.5)
    C.camera_look((-4.2, -5.0, 1.7), (0, 0, 0.6), lens=40)
    C.render(prefix + "_front.png")
    C.camera_look((4.0, 5.2, 1.9), (0, 0, 0.6), lens=40)
    C.render(prefix + "_rear.png")
    C.camera_look((7.5, 0, 0.9), (0, 0, 0.6), lens=45)
    C.render(prefix + "_side.png")
    if cockpit:
        cam = bpy.data.objects["Cam_Cockpit"].location
        C.camera_look(tuple(cam), (cam.x + 0.05, cam.y - 2.0, cam.z - 0.35), lens=22)
        C.render(prefix + "_cockpit.png")
    # doors open shot
    for d, a in (("Door_L", 1), ("Door_R", -1)):
        o = bpy.data.objects.get(d)
        if o:
            o.rotation_euler.z = math.radians(-60 * a)
    C.camera_look((-3.6, -1.6, 2.6), (0, 0, 0.6), lens=35)
    C.render(prefix + "_doors.png")
    for d in ("Door_L", "Door_R"):
        o = bpy.data.objects.get(d)
        if o:
            o.rotation_euler.z = 0
