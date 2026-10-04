# Audio credits

Most of the game's audio is synthesised in code (`audio/tools/gen_*.py`). The
field recordings below are used as source material. Every one was checked on
its own freesound.org page; all are **CC0 (public domain)**, so attribution is
not required. They are listed as a courtesy and so the build is reproducible.
No CC-BY-NC, Sampling+ or other restricted licences are used.

Raw downloads are fetched by `python3 audio/tools/fetch_sources.py` into
`build/sources/` (gitignored); the game files are generated from them.

## Ambience and night oddities (`audio/tools/gen_amb.py`)

Licence for every row: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/).

| Key | Title | Author | URL | Used in |
|---|---|---|---|---|
| mag_kp2 | Australian Magpie (family calling, Kings Park, Perth) | dbache | https://freesound.org/s/353060/ | amb_bird_magpie_01, _02; amb_kingspark_day, amb_river_day, amb_suburbs_day |
| mag_dl | AustralianMagpies.wav | DangerLaef | https://freesound.org/s/319767/ | amb_bird_magpie_03; amb_kingspark_day, amb_river_day, amb_suburbs_day |
| kook_kp | Kookaburra Australian Jackass.wav (Kings Park, WA) | dbache | https://freesound.org/s/671250/ | amb_bird_kookaburra_01, _02; amb_kingspark_day |
| lorikeets | Rainbow Lorikeets.wav | dannydandanshababaloo | https://freesound.org/s/593156/ | amb_kingspark_day |
| cockatoo_perth | Perth Black Cockatoos at Dusk | bushtobazaar | https://freesound.org/s/514053/ | amb_kingspark_day |
| walyunga | Walyunga National Park, Western Australia.wav | bushtobazaar | https://freesound.org/s/523549/ | amb_kingspark_day |
| raven_db | Ravens (Australian raven) | dbache | https://freesound.org/s/555187/ | amb_bird_raven_01..03; amb_kingspark_day, amb_suburbs_day, amb_suburbs_night |
| raven_yell | Murder Of Crows at Yellagonga (Perth: Australian ravens) | samarobryn | https://freesound.org/s/400395/ | amb_suburbs_day, amb_suburbs_night |
| wagtail1 | Australian Willy Wagtail | Inkahootz81 | https://freesound.org/s/388734/ | amb_bird_wagtail_01, _02; amb_suburbs_day |
| boobook1 | Boobook Owl / Mopoke | Monkey Pants | https://freesound.org/s/409436/ | amb_kingspark_night |
| pobble1 | Pobblebonk (Eastern Banjo Frog) Call with Cicadas.wav | volition74 | https://freesound.org/s/512775/ | amb_kingspark_night |
| pobble2 | pobblebonk frogs near an airport | Hypo_Mix | https://freesound.org/s/530274/ | amb_kingspark_night |
| crickets_sub | Night_Crickets_Wind suburban adelaide.wav | roisin.gleeson | https://freesound.org/s/699142/ | amb_kingspark_night, amb_river_night, amb_suburbs_night |
| hydepark | Atmos, Park, Hyde Park, Perth, Light Traffic, Children.wav | arefrashidan | https://freesound.org/s/691375/ | amb_cbd_day, amb_suburbs_day |
| traffic_peak | Car Traffic Main Road Peak Hour (Brisbane) | EarJuice | https://freesound.org/s/680419/ | amb_cbd_day, amb_northbridge_day, amb_freeway_day |
| traffic_night | traffic ambience at night.wav (Australian suburbs) | soundofsong | https://freesound.org/s/640635/ | amb_cbd_night, amb_northbridge_night, amb_suburbs_night |
| bar_wa | Bar Atmos (Melbourne) | veronicalyn | https://freesound.org/s/490288/ | amb_northbridge_day, amb_northbridge_night, amb_carmeet |
| pub_crowd | Bar crowd ambience | wjb_88 | https://freesound.org/s/828867/ | amb_northbridge_night |
| highway_wa | Afternoon Highway.wav (Western Australia) | Kalaji | https://freesound.org/s/418097/ | amb_freeway_night |
| freeway | Traffic passing by on freeway | nickeverest69 | https://freesound.org/s/795499/ | amb_freeway_day |
| lawnmower | lawnmower mowing lawn drive around property far distant and close passes.flac | kyles | https://freesound.org/s/637653/ | amb_suburbs_day |
| sprinkler | BlaccardSprinklerLoop.wav | blaccard | https://freesound.org/s/347025/ | amb_suburbs_day, amb_suburbs_night |
| dogs_far | Distant Dogs | IENBA | https://freesound.org/s/820267/ | amb_dog_bark_far_01..03; amb_suburbs_day, amb_suburbs_night |
| dog_far2 | dog-distant barking.wav | alberto59 | https://freesound.org/s/615258/ | amb_dog_bark_far_01..03 (pool); amb_suburbs_day, amb_suburbs_night |
| beach_day | Beach Atmos Australia Day | DeppStudios1977 | https://freesound.org/s/790724/ | amb_beach_day |
| beach_night | Australian Beach Night Waves | DeppStudios1977 | https://freesound.org/s/790720/ | amb_beach_night |
| laps_horn | Australia - Ocean Water Laps CU Active w Ship Horn, Bird and People in BG.wav | earsaregood | https://freesound.org/s/470781/ | amb_fremantle_day |
| lapping | Ocean-WavesLapping | rj13 | https://freesound.org/s/570955/ | amb_river_day, amb_river_night, amb_fremantle_night |
| ferry | boat engine small ferry bassy NYC, USA.flac | kyles | https://freesound.org/s/452924/ | amb_river_day |
| freo_train | Railway Line & Signal Lights (freight train leaving Fremantle port) | dbache | https://freesound.org/s/351425/ | amb_fremantle_day |

Fully synthesised (no recordings): pedestrian-crossing signals (amb_ped_*),
sirens, Transperth train pass-bys, level-crossing bells, silver gulls, wind in
the gums, traffic pass-bys, air-con units, club bass, car stereo, engine idles,
ship horns, port clanks, all of `audio/oddity/`.
