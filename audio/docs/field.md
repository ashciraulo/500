# Bird-watching and fishing (`audio/field/`, `gen_field.py`)

Everything the field journal plays, named the way the bird-watching code asks
for it. All mono (birds 3D-ready). A name without its `_NN` picks a random
variant: `Audio.play_at("field/bird_galah", pos, 0.0, "Ambience")`. The game
guards each call with `Audio.has(name)`, so a missing sound just plays nothing.
Calls are loudness-matched (-20 LUFS, never above -1 dBTP), so a synthesised
whistle sits level with a recorded cockatoo; set distance with `volume_db`.

Regenerate with `python3 audio/tools/gen_field.py [birds|ui|fish]`
(synthesised species live in `field_birds.py`).

## Aliases

Some names borrow a sound that already exists elsewhere (`Audio.ALIASES`).
Drop a real file with the alias's name in `audio/field/` and it wins.

| Name | Plays |
|---|---|
| field/bird_australian_magpie | amb/amb_bird_magpie_01..03 (recordings) |
| field/bird_laughing_kookaburra | amb/amb_bird_kookaburra_01..02 (recordings) |
| field/bird_australian_raven | amb/amb_bird_raven_01..03 (recordings) |
| field/flush | traffic/traffic_wings_takeoff_01..02 (a bird spooked off) |
| field/reel | field/reel_loop |
| field/splash | field/splash_small |

## Birds (`field/bird_<species>_NN`)

| Species | Variants | When | Source |
|---|---|---|---|
| carnabys_black_cockatoo | 3 | day, dusk | Recording: wailing "wee-la" flying over Perth (cockatoo_perth) |
| rainbow_lorikeet | 3 | day | Recording: metallic screeching (lorikeets) |
| southern_boobook | 2 | night | Recording: "boo-book" pairs (boobook1) |
| willie_wagtail | 3 | day; _03 night | Recording: chatter (wagtail1); _03 is the synthesised night song, "sweet pretty creature" |
| australian_pelican | 2 | day | Nearly silent: a hoarse grunt and the hollow clap of the bill |
| black_swan | 3 | day, dusk | Soft reedy bugle notes in a short series |
| tawny_frogmouth | 2 | night | Deep soft "oom-oom-oom", about four a second |
| silver_gull | 3 | day | Harsh nasal "kee-arr" |
| australian_white_ibis | 2 | day | Hoarse, low, grunting honks |
| white_faced_heron | 3 | day | One gravelly "graak" |
| galah | 3 | day | Shrill metallic "chet", in twos and threes |
| little_corella | 2 | day | Long wavering screech; _02 is a small flock |
| red_wattlebird | 3 | day | Harsh guttural "chock" |
| new_holland_honeyeater | 3 | day | Sharp "chik" and a fast thin run |
| singing_honeyeater | 2 | day | Rolling musical "prrip-prrip" |
| australian_ringneck | 3 | day | Three ringing notes, "twenty-eight" |
| grey_butcherbird | 3 | day | Rich fluting phrase |
| laughing_dove | 2 | day | Soft bubbling laughing coo |
| spotted_dove | 3 | day | "coo, crrr-coo" |
| crested_tern | 3 | day | Grating "kirrick" |
| pied_oystercatcher | 2 | day | Piping "kleep" |
| pacific_black_duck | 3 | day | Descending quacks |
| purple_swamphen | 3 | day | Screeching "kee-ow" |
| eurasian_coot | 2 | day | Sharp nasal "kowk" |
| osprey | 3 | day | High plaintive "cheep-cheep" |
| nankeen_kestrel | 3 | day | Shrill "kee-kee-kee" |
| eastern_barn_owl | 2 | night | Long hissing screech |
| nankeen_night_heron | 3 | dusk, night | Deep harsh "kwok" |
| rainbow_bee_eater | 3 | spring, summer | Rolling liquid "prrp-prrp" high up |
| splendid_fairywren | 2 | day | High reeling trill |
| welcome_swallow | 3 | day | Quick cheerful twitter |
| rock_dove | 3 | day | Throaty rolling "oo-roo-coo" with a burr |
| little_pied_cormorant | 3 | day | Near silent: a few soft guttural "uk-uk" croaks |
| australasian_darter | 3 | day | Dry clicking "kah-kah-kah" rattle |
| great_egret | 3 | day | Loud harsh low "kraak" |
| musk_duck | 3 | day | The male's display: a water "plonk", a shrill whistle, a grunt |

Everything but the recordings is synthesised from field-guide descriptions
(whistles, screeches, trills, coos and croaks): no CC0 recordings of those
species were reachable.

## Wrong calls (`field/wrong_*`)

Quiet, far off and soft-edged, never jumpy: for after midnight and the mystery.

| File | What is wrong |
|---|---|
| wrong_magpie_song | A magpie's carol drifts mid-phrase into the midnight station's falling interval (E D C G), a little flat, as if learned off a car radio |
| wrong_frogmouth | A frogmouth calling metronome-regular: every note the same, exactly half a second apart, for far too long |
| wrong_boobook | (spare) "boo-book-book": one note more, a semitone too high |
| wrong_magpie_reversed | (spare) A magpie carol backwards and slowed, on worn tape |
| wrong_frogmouth_answer | (spare) A frogmouth answered by itself, note for note, from nearer than it called |
| wrong_kookaburra_slow | (spare) The kookaburras laughing at half speed, trailing off early |

## Binoculars, camera and journal

| File | When | What it is |
|---|---|---|
| binoculars_up / binoculars_down | B pressed | Strap rustle; up = rubber eyecups and a knurled wheel, down = soft bump on the chest |
| focus_tick | each step of the dial's needle | One fine detent of the focus ring (tiny, soft) |
| focus_hit | needle caught in a sharp arc | The ring clicks home, the glass rings faintly |
| focus_miss | pressed outside the arcs | A dull rubbery slip |
| shutter | the photo | Old film SLR: release, mirror up and down, two cloth curtains, wind-on lever |
| film_full | last frame used | The wind lever jams, then the rewind crank's dry whirr |
| journal_open / journal_close / journal_page | the journal (J) | Cloth-bound notebook: spine creak, paper flop, soft shut, page turn |
| journal_new_entry | a new species | A quick pencil note, then a rubber stamp |

## Fishing

| File | Loop? | What it is |
|---|---|---|
| cast_01..03 | no | Bail flips, rod swish, line peeling off, the lure landing far off |
| lure_plop_01..03 | no | Lure or bait hitting the water |
| bite_nibble_01..03 | no | Twitches at the rod tip, a dimple on the water |
| strike | no | Fast rod sweep, line snapping taut, swirl |
| reel_loop | yes (2 s) | Gear whirr and pawl ticks; pitch it with reel speed |
| line_tension_loop | yes (4 s) | Line singing, rod creak, drag clicks; fade up with tension |
| splash_small / splash_big | no | A fish thrashing at the surface |
| line_snap | no | Crack, rod springs back, slack line |
| landed_flop | no | A fish flopping on jetty boards |
| bucket_drop | no | Into the bucket |
| esky_lid | no | Lid creak, ice shifting, foam-dulled thump and latch |
| drag_01..02 | no | The drag ratchet screaming as a fish starts a run, then tiring |
| rod_out | no | Rod bag knock, tackle box rattle, the bail clicked over |
| reel_in | no | A quick wind-in, the lure knocking up against the rod tip |

Loops: `Audio.stream("field/reel_loop", true)`. Jetty ambience is
`amb/place/place_jetty_loop` and `place_jetty_night_loop` (docs/amb.md),
played near map points of kind `jetty` or `fishing_spot`, or through
`Audio.ambience.add_place("jetty", pos)`.

Encodes: calls Vorbis q3 at 32 kHz, foley q4.
