# Music

First-pass placeholder music: Italian 1960s/70s lounge and library music that sounds like it was played off a worn VHS tape. Every piece is composed in code (real chord progressions, written melodies, humanised timing and velocity), rendered with FluidSynth and the MIT-licensed FluidR3_GM soundfont, then mixed and run through a tape chain in numpy. The chain adds wow (about 0.5 Hz) and flutter (about 6 Hz) by fractional-delay resampling, gentle saturation, a low-end head bump, high-frequency roll-off around 10 kHz, hiss, occasional short dropouts and mild stereo narrowing.

All files are 48 kHz stereo OGG Vorbis (q6) at -16 LUFS integrated, with true peak below -1 dBTP. The one exception is `mus_mission_tension_intensity` (see the table).

| File | Loop? | Use | Length | BPM / key | Instruments |
|---|---|---|---|---|---|
| mus_main_theme | yes, seamless | Title screen / garage | 2:20 (56 bars) | 96, D major | Vibraphone lead (A), flute (B), whistle (A'), drawbar organ, nylon bossa guitar, upright bass, brush kit, slow strings, choir oohs |
| mus_mission_tension_base | yes, seamless | Mission groove | 1:36 (48 bars) | 120, C minor | Jazz kit, finger bass ostinato, Rhodes stabs, muted guitar chops, muted trumpet melody |
| mus_mission_tension_intensity | yes, seamless | Layer the game fades in on top of the base when time runs low. Same length, BPM and sample grid as the base: start both together. It is mastered *relative to the base* (about -20 LUFS on its own): at 0 dB it gives the intended full mix. | 1:36 | 120, C minor | Tremolo strings, string-section melody, harpsichord 16ths, brass stabs, timpani, congas/bongos/shaker |
| mus_cinquecento_01 | no, clean ending | Radio Cinquecento (day) "Passeggiata" | 2:58 | 108 light swing, G major | Mandolin (tremolo) lead, Italian accordion, nylon guitar, upright bass (two-feel and walking), brushes, organ, strings |
| mus_cinquecento_02 | no | Radio Cinquecento "Spiaggia" (bossa) | 2:12 | 132, A minor | Wordless voice (oohs) lead, flute, nylon bossa guitar, upright bass, brushes with clave, Rhodes, strings |
| mus_cinquecento_03 | no | Radio Cinquecento "Autostrada" (library funk) | 2:48 | 100, E dorian | Rhodes lead, percussive organ, flute, wah funk guitar, clavinet, finger bass, room kit, bongos/congas |
| mus_cinquecento_04 | no | Radio Cinquecento "Valzer del Molo" (waltz, 3/4) | 2:13 | 132, F major / D minor | Italian accordion lead, violin, mandolin tremolo, nylon guitar, upright bass, brushes |
| mus_cinquecento_05 | no | Radio Cinquecento "Ballata" (slow ballad) | 2:11 | 72, Eb major | Piano lead, celesta, slow strings, upright bass, brushes |
| mus_nottefm_01 | no, fades | Notte FM (night) | 2:37 | 64, Db major | Two detuned drifting warm pads, halo pad, new-age pad drone, sparse Rhodes |
| mus_nottefm_02 | no, fades | Notte FM | 2:15 | 60, E minor | Detuned bowed pads, sweep pad, drone, sparse detuned EP |
| mus_nottefm_03 | no, fades | Notte FM | 2:14 | 75, A major | Polysynth pads, crystal arpeggio, synth-bass drone, Rhodes, soft 808 pulse |
| mus_nottefm_04 | no, fades | Notte FM | 2:25 | 56, F lydian | Choir pads, synth strings, drone, sparse vibraphone |
| mus_home_theme | yes, seamless | Home: the day station heard from the next room | 2:00 (40 bars) | 80, F major | Clarinet lead, vibraphone, fingerpicked nylon guitar, bass, brushes, organ; low-passed with a small-room reverb |
| mus_timetrial_loop | yes, seamless | Time trial | 1:20 (48 bars) | 144, A major | Brass section and trumpet lead, rock organ, organ stabs, clean guitar chops, driving finger bass, room kit, tambourine, latin percussion |
| mus_sting_complete | no | Mission complete | 5.5 s | 96, D major | Vibraphone run, flute, organ, bass, ride |
| mus_sting_failed | no | Mission failed | 6.5 s | 96, D minor | Muted trumpet, vibraphone, organ, bass |
| mus_sting_tier_unlock | no | Tier unlocked | 7.5 s | 120, D major | Harp arpeggios, celesta, vibraphone, strings swell |
| mus_sting_new_car | no | New car | 8 s | 120, D major | Main-theme motif on vibraphone and whistle, bossa band |
| mus_storm_01 | no | Storm version of Cinquecento 01 | 3:35 | 90, D major (down a fourth) | Nylon guitar lead, clarinet, church organ, detuned warm pad, brushes; darker, duller tape |
| mus_storm_02 | no, fades | Storm version of Notte FM 02 | 2:39 | 52, C# minor | Bowed pads, synth strings, contrabass drone, distant timpani rolls, vibraphone |
| mus_midnight_theme | yes, seamless | Midnight: the main theme slowed, warped and partly reversed | 1:02.5 | 76.8 (96 slowed to 80 %), about Bb major | Main theme intro + A section, slowed 80 %, reversed bars, reverse-reverb swells, heavy wow |

Loops are rendered with a bar of pre-roll and all release and reverb tails past the loop end folded back onto the start. Every effect in the chain (EQ, reverb, wow/flutter, hiss, dropouts, limiter) works circularly, so the join is seamless. Each loop is cut to an exact bar boundary: the BPMs were picked so that a beat is a whole number of samples at 48 kHz. Radio tracks have real endings, with a final chord and a short fade on the tail. In Godot, turn on looping for the six loop files, either in the import settings (`loop=true`) or in code.

## Regenerating and replacing

Run `python3 audio/tools/gen_music.py` from any directory to rebuild everything. Add track names (for example `python3 audio/tools/gen_music.py mus_main_theme mus_sting_failed`) to rebuild only those, or `--list` to see the names. The output is deterministic. The script needs `fluidsynth` (2.3), `/usr/share/sounds/sf2/FluidR3_GM.sf2`, `ffmpeg` and python3 with numpy, scipy, soundfile and pyloudnorm. Compositions are in `audio/tools/music_tracks_main.py` and `music_tracks_more.py`. Harmony, MIDI, rendering and the tape chain are in `music_core.py`, and the accompaniment patterns are in `music_patterns.py`. Rendered stems are cached in the system temp directory, and `MUSIC_DEBUG=1` prints the level of each stem.

To replace a track with your own, export it as a stereo file at about -16 LUFS integrated (peaks at or below -1 dBTP), encode it to OGG Vorbis, and drop it in `audio/music/` under the same filename. Then don't rerun the generator for that name, because it would overwrite your file. Loops should start and end on the beat with no fade. The two mission files must be the same length and start on the same sample, and the intensity file should be mixed to sit on top of the base at 0 dB.
