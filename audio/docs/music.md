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
| mus_cinquecento_06 | no | Radio Cinquecento "Alba" (dawn bossa) | 2:36 | 112, E major | Piano lead (A), nylon guitar lead (A2, B2), bossa guitar, piano comp, upright bass, brushes with clave, strings |
| mus_cinquecento_07 | no | Radio Cinquecento "Colazione" (breakfast two-beat; last chorus up a tone to D) | 2:21 | 152, C major | Whistle lead, xylophone, glockenspiel, steel-string guitar and pizzicato strings on 2 and 4, upright bass, room kit with tambourine and claps, strings |
| mus_cinquecento_08 | no | Radio Cinquecento "Polvere" (spaghetti-western gallop) | 2:56 | 100, D minor | Low twang electric guitar lead, whistle, trumpet (B), galloping steel-string guitar, woodblock hooves, choir oohs, strings, timpani, tubular bell, picked bass |
| mus_cinquecento_09 | no | Radio Cinquecento "Bar Sport" (organ-trio shuffle) | 2:22 | 120 shuffle, Bb major | Drawbar organ lead, jazz guitar lead (B and second A), percussive organ comp, four-to-the-bar guitar, walking upright bass, jazz kit |
| mus_cinquecento_10 | no | Radio Cinquecento "Riviera" (cha-cha) | 2:26 | 118, Ab major | Alto sax lead, violin (B), piano montuno, upright bass, cowbell, guiro, congas, timbales, strings |
| mus_cinquecento_11 | no | Radio Cinquecento "Onda" (sunny surf pop) | 2:33 | 140, A major | 12-string guitar lead (tremolo-picked last chorus), Hawaiian steel guitar (B), percussive organ (B2), clean rhythm guitar, finger bass, room kit with tambourine, organ pad |
| mus_cinquecento_12 | no | Radio Cinquecento "Barocco" (baroque pop) | 2:30 | 104, B minor | Coupled harpsichord lead and arpeggios, string-section lead (B), oboe, strings, picked bass, pop kit with tambourine; ends on B major |
| mus_cinquecento_13 | no | Radio Cinquecento "Tramonto" (golden-hour serenade, 6/8) | 2:34 | 6/8, eighth = 126, D major | Mandolin tremolo lead, cello (B), fingerpicked nylon guitar, upright bass, soft brushes, strings |
| mus_cinquecento_14 | no | Radio Cinquecento "Pomeriggio" (samba) | 2:48 | 104, F minor | Flute lead, Rhodes lead (B) and partido-alto comp, nylon guitar, finger bass, samba kit with shaker, rim and agogo, strings |
| mus_cinquecento_15 | no | Radio Cinquecento "Crepuscolo" (dusk ballad) | 2:46 | 66, Db major | Muted trumpet lead, vibraphone, harp, jazz guitar, upright bass, brushes, strings |
| mus_nottefm_01 | no, fades | Notte FM (night) | 2:37 | 64, Db major | Two detuned drifting warm pads, halo pad, new-age pad drone, sparse Rhodes |
| mus_nottefm_02 | no, fades | Notte FM | 2:15 | 60, E minor | Detuned bowed pads, sweep pad, drone, sparse detuned EP |
| mus_nottefm_03 | no, fades | Notte FM | 2:14 | 75, A major | Polysynth pads, crystal arpeggio, synth-bass drone, Rhodes, soft 808 pulse |
| mus_nottefm_04 | no, fades | Notte FM | 2:25 | 56, F lydian | Choir pads, synth strings, drone, sparse vibraphone |
| mus_nottefm_05 | no | Notte FM "Velluto" (lo-fi hip-hop) | 2:52 | 80 swung, Ab major | Rhodes lead, detuned Rhodes comping, finger bass, dusty swung boom-bap kit, warm pad |
| mus_nottefm_06 | no | Notte FM "Lungomare" (late-night city pop) | 2:30 | 92, E major | Alto sax lead, EP lead (one chorus), EP comping, fretless bass, clean guitar chops, soft kit, strings |
| mus_nottefm_07 | no | Notte FM "Eco del porto" (dub) | 2:38 | 72, G minor | Melodica (harmonica + reed organ) through tape echo, deep bass line, one-drop kit, echoing guitar skank, organ bubble; two dub breakdowns |
| mus_nottefm_08 | no | Notte FM "Notturno blu" (3/4 nocturne) | 2:36 | 84 in 3/4, D minor | Vibraphone lead and comping, upright bass (two-feel, walking chorus), faint brushes |
| mus_nottefm_09 | no | Notte FM "Isola" (Balearic) | 2:46 | 100, D major | Nylon guitar lead, flute, echoing clean-guitar arpeggios, finger bass, congas and shaker, warm pad |
| mus_nottefm_10 | no | Notte FM "Neon lento" (chillwave) | 2:53 | 84, Bb major | Detuned square lead with sine double, wide detuned polysynth pads, echoing synth arpeggio, synth bass, soft 808; heavy wow |
| mus_nottefm_11 | no | Notte FM "Ninna nanna" | 2:57 | 66, C major | Felt (low-passed) piano lead and rolling left hand, cello lead and counterline |
| mus_nottefm_12 | no | Notte FM "Pioggia fine" (trip-hop) | 2:56 | 82, B minor | Palm-muted guitar riff, slow strings melody, sparse Rhodes, sub synth bass, heavy room kit, pad |
| mus_nottefm_13 | no | Notte FM "Le tre di notte" (3 am ballad) | 3:14 | 66 light swing, Eb major | Rhodes lead (head, improvised chorus, head), detuned Rhodes comping, upright bass, brushes, faint strings |
| mus_nottefm_14 | no, fades | Notte FM "Ore piccole" (beatless drift) | 2:38 | 52, B lydian | Detuned bowed-glass pads, halo pad, sine sub, celesta and music box through echo, slow crystal arpeggio |
| mus_ident_cinquecento_01..04 | no | Radio Cinquecento idents, dropped between songs: the four-note "Cin-que-cen-to" signature (D B G D) sung by jingle singers on oohs (01), on mandolin and accordion (02), organ and brass for drive time (03), flute and harp for mornings (04) | 4-5.5 s | 96-128, G/D major | `music_tracks_idents.py` |
| mus_ident_nottefm_01..03 | no | Notte FM idents: the same shape slowed and lowered ("Not-te F-M"), on Rhodes over a pad (01), vibes and soft voices (02), a glassy synth arpeggio for the small hours (03) | 6-7 s | 62-76, Db/Bb minor/Ab | `music_tracks_idents.py` |
| mus_radio_pips | no | The time signal before the next song at 6:00, 12:00 and 18:00: five short 1 kHz pips and a long sixth, band-limited, -20 LUFS | 6.4 s | | `music_tracks_idents.py` |
| mus_home_theme | yes, seamless | Home: the day station heard from the next room | 2:00 (40 bars) | 80, F major | Clarinet lead, vibraphone, fingerpicked nylon guitar, bass, brushes, organ; low-passed with a small-room reverb |
| mus_timetrial_loop | yes, seamless | Time trial | 1:20 (48 bars) | 144, A major | Brass section and trumpet lead, rock organ, organ stabs, clean guitar chops, driving finger bass, room kit, tambourine, latin percussion |
| mus_sting_complete | no | Mission complete | 5.5 s | 96, D major | Vibraphone run, flute, organ, bass, ride |
| mus_sting_failed | no | Mission failed | 6.5 s | 96, D minor | Muted trumpet, vibraphone, organ, bass |
| mus_sting_tier_unlock | no | Tier unlocked | 7.5 s | 120, D major | Harp arpeggios, celesta, vibraphone, strings swell |
| mus_sting_race_win | no | Beat the train | 5.5 s | 132, G major | Climbing vibraphone run and muted trumpet over a brushed train shuffle, two-note whistle call (high-low, like the crossing horn), crash on the last chord. `Audio.sting("race_win")` |
| mus_sting_new_car | no | New car | 8 s | 120, D major | Main-theme motif on vibraphone and whistle, bossa band |
| mus_field_journal | yes | Under the field journal screen (J) | 56 s | 68, G major | Nylon guitar arpeggios, vibraphone on the idents' motif (D B G D) slowed right down, warm pad, fretless bass; no drums |
| mus_field_dawn | no | First light (6:00), radio off, played by Audio.hooks | 16 s | 64, G major | Pad swell, the motif climbing on celesta, a flute answer, one strummed chord |
| mus_field_dusk | no | Dusk (19:00), radio off, played by Audio.hooks | 17 s | 60, E minor | The motif falling on vibraphone over a slow guitar arpeggio, the last chord left open |
| mus_field_new_species | no | A new species in the journal | 6 s | 84, G major | Harp chord and the motif on celesta |
| mus_storm_01 | no | Storm version of Cinquecento 01 | 3:35 | 90, D major (down a fourth) | Nylon guitar lead, clarinet, church organ, detuned warm pad, brushes; darker, duller tape |
| mus_storm_02 | no, fades | Storm version of Notte FM 02 | 2:39 | 52, C# minor | Bowed pads, synth strings, contrabass drone, distant timpani rolls, vibraphone |
| mus_midnight_theme | yes, seamless | Midnight: the main theme slowed, warped and partly reversed | 1:02.5 | 76.8 (96 slowed to 80 %), about Bb major | Main theme intro + A section, slowed 80 %, reversed bars, reverse-reverb swells, heavy wow |

Radio Cinquecento has fifteen tracks. Its running order follows `audio/music/programme_cinquecento.json`, which gives each track its Italian title (`titles`) and the time-of-day blocks it suits (`blocks`): morning (05-10), day (10-16), evening (16-20), night (20-01) and late (01-05). Every block has at least five tracks; the day station keeps playing at night, but only its mellower pieces.

Loops are rendered with a bar of pre-roll and all release and reverb tails past the loop end folded back onto the start. Every effect in the chain (EQ, reverb, wow/flutter, hiss, dropouts, limiter) works circularly, so the join is seamless. Each loop is cut to an exact bar boundary: the BPMs were picked so that a beat is a whole number of samples at 48 kHz. Radio tracks have real endings, with a final chord and a short fade on the tail. In Godot, turn on looping for the six loop files, either in the import settings (`loop=true`) or in code.

Notte FM has fourteen pieces. Its running order follows `audio/music/programme_nottefm.json`, which gives each track an Italian title and the blocks of the day it suits: morning (5-10), day (10-16), evening (16-20), night (20-01) and late (01-05). Every block has at least five tracks. The beat-driven pieces (05, 06, 07, 10, 12) sit in the evening and night, the beatless and slow pieces in the late block, and the brighter ones also play in the day. Notte FM 05-14 are in `audio/tools/music_tracks_notte.py`.

## Regenerating and replacing

Run `python3 audio/tools/gen_music.py` from any directory to rebuild everything. Add track names (for example `python3 audio/tools/gen_music.py mus_main_theme mus_sting_failed`) to rebuild only those, or `--list` to see the names. The output is deterministic. The script needs `fluidsynth` (2.3), `/usr/share/sounds/sf2/FluidR3_GM.sf2`, `ffmpeg` and python3 with numpy, scipy, soundfile and pyloudnorm. Compositions are in `audio/tools/music_tracks_main.py`, `music_tracks_more.py` and `music_tracks_cinq.py` (Cinquecento 06-15). Harmony, MIDI, rendering and the tape chain are in `music_core.py`, and the accompaniment patterns are in `music_patterns.py`. Rendered stems are cached in the system temp directory, and `MUSIC_DEBUG=1` prints the level of each stem.

To replace a track with your own, export it as a stereo file at about -16 LUFS integrated (peaks at or below -1 dBTP), encode it to OGG Vorbis, and drop it in `audio/music/` under the same filename. Then don't rerun the generator for that name, because it would overwrite your file. Loops should start and end on the beat with no fade. The two mission files must be the same length and start on the same sample, and the intensity file should be mixed to sit on top of the base at 0 dB.
