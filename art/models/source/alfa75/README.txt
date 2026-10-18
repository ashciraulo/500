Alfa Romeo 75 - Driftwood FM export
===================================

alfa75.blend - a self-contained copy of the Driftwood FM Alfa Romeo 75 car model.
All textures (Driftwood FM rear sticker) are packed into the file, and there are no linked libraries, so it can be moved anywhere.

Made with Blender 5.2.2 LTS. Open it in 5.2.2 or newer.

Model
- Right-hand drive (RHD) interior, with the instrument cluster and dash hood.
- Paint colour: #B9B2A6 (warm grey).
- Driftwood FM sticker on the rear window.

Hierarchy
- Alfa75_Body   - root empty for the body, interior and lights. Move/rotate this.
- Alfa75_Wheels - root empty for the wheels.

Cameras
- Cam_Rear34_Chase, Cam_Front34, Cam_Side, Cam_Overhead, Cam_Driver, Cam_Interior_OTS

Lights
- Text block "alfa_lights.py" (Text Editor) defines:
      set_lights(lights=0, brake=0, reverse=0)
  Run the text block, then call set_lights(...) with 1 to turn a group on, e.g.
  set_lights(lights=1, brake=1).
- The file is saved with all lights OFF.
- Drivers don't evaluate in background (-b) renders, so call set_lights() from your
  render script rather than relying on drivers.

Credits
- Based on a CC BY 4.0 model. See CREDITS.txt. The credit line must go in any video
  description that uses this car.

In this repo: the packed Arial Bold and Consolas fonts were swapped for Blender's
built-in font (they aren't ours to share). The game doesn't use the plate or radio
text as drawn here.
