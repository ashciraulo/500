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
| mag_kp2 | Australian Magpie (family calling, Kings Park, Perth) | dbache | https://freesound.org/s/353060/ | amb_bird_magpie_01, _02; amb_kingspark_day, amb_river_day, amb_suburbs_day; place_bush, place_lookout, place_riverside |
| mag_dl | AustralianMagpies.wav | DangerLaef | https://freesound.org/s/319767/ | amb_bird_magpie_03; amb_kingspark_day, amb_river_day, amb_suburbs_day; place_bush, place_lookout, place_riverside |
| kook_kp | Kookaburra Australian Jackass.wav (Kings Park, WA) | dbache | https://freesound.org/s/671250/ | amb_bird_kookaburra_01, _02; amb_kingspark_day |
| lorikeets | Rainbow Lorikeets.wav | dannydandanshababaloo | https://freesound.org/s/593156/ | amb_kingspark_day; field/bird_rainbow_lorikeet_01..03 |
| cockatoo_perth | Perth Black Cockatoos at Dusk | bushtobazaar | https://freesound.org/s/514053/ | amb_kingspark_day; field/bird_carnabys_black_cockatoo_01..03 |
| walyunga | Walyunga National Park, Western Australia.wav | bushtobazaar | https://freesound.org/s/523549/ | amb_kingspark_day; place_bush |
| raven_db | Ravens (Australian raven) | dbache | https://freesound.org/s/555187/ | amb_bird_raven_01..03; amb_kingspark_day, amb_suburbs_day, amb_suburbs_night |
| raven_yell | Murder Of Crows at Yellagonga (Perth: Australian ravens) | samarobryn | https://freesound.org/s/400395/ | amb_suburbs_day, amb_suburbs_night |
| wagtail1 | Australian Willy Wagtail | Inkahootz81 | https://freesound.org/s/388734/ | amb_bird_wagtail_01, _02; field/bird_willie_wagtail_01, _02; amb_suburbs_day; place_bush |
| boobook1 | Boobook Owl / Mopoke | Monkey Pants | https://freesound.org/s/409436/ | amb_kingspark_night; place_bush_night; field/bird_southern_boobook_01..02, field/wrong_boobook |
| pobble1 | Pobblebonk (Eastern Banjo Frog) Call with Cicadas.wav | volition74 | https://freesound.org/s/512775/ | amb_kingspark_night; place_riverside_night |
| pobble2 | pobblebonk frogs near an airport | Hypo_Mix | https://freesound.org/s/530274/ | amb_kingspark_night; place_riverside_night |
| crickets_sub | Night_Crickets_Wind suburban adelaide.wav | roisin.gleeson | https://freesound.org/s/699142/ | amb_kingspark_night, amb_river_night, amb_suburbs_night; place_bush_night, place_lookout_night, place_riverside_night |
| hydepark | Atmos, Park, Hyde Park, Perth, Light Traffic, Children.wav | arefrashidan | https://freesound.org/s/691375/ | amb_cbd_day, amb_suburbs_day |
| traffic_peak | Car Traffic Main Road Peak Hour (Brisbane) | EarJuice | https://freesound.org/s/680419/ | amb_cbd_day, amb_northbridge_day, amb_freeway_day; place_carpark |
| traffic_night | traffic ambience at night.wav (Australian suburbs) | soundofsong | https://freesound.org/s/640635/ | amb_cbd_night, amb_northbridge_night, amb_suburbs_night; place_carpark_night |
| bar_wa | Bar Atmos (Melbourne) | veronicalyn | https://freesound.org/s/490288/ | amb_northbridge_day, amb_northbridge_night, amb_carmeet; place_quay; traffic_crowd_small_loop, traffic_crowd_busy_loop |
| pub_crowd | Bar crowd ambience | wjb_88 | https://freesound.org/s/828867/ | amb_northbridge_night; traffic_crowd_busy_loop |
| highway_wa | Afternoon Highway.wav (Western Australia) | Kalaji | https://freesound.org/s/418097/ | amb_freeway_night |
| freeway | Traffic passing by on freeway | nickeverest69 | https://freesound.org/s/795499/ | amb_freeway_day |
| lawnmower | lawnmower mowing lawn drive around property far distant and close passes.flac | kyles | https://freesound.org/s/637653/ | amb_suburbs_day |
| sprinkler | BlaccardSprinklerLoop.wav | blaccard | https://freesound.org/s/347025/ | amb_suburbs_day, amb_suburbs_night |
| dogs_far | Distant Dogs | IENBA | https://freesound.org/s/820267/ | amb_dog_bark_far_01..03; amb_suburbs_day, amb_suburbs_night |
| dog_far2 | dog-distant barking.wav | alberto59 | https://freesound.org/s/615258/ | amb_dog_bark_far_01..03 (pool); amb_suburbs_day, amb_suburbs_night |
| beach_day | Beach Atmos Australia Day | DeppStudios1977 | https://freesound.org/s/790724/ | amb_beach_day; place_beach |
| beach_night | Australian Beach Night Waves | DeppStudios1977 | https://freesound.org/s/790720/ | amb_beach_night; place_beach_night |
| laps_horn | Australia - Ocean Water Laps CU Active w Ship Horn, Bird and People in BG.wav | earsaregood | https://freesound.org/s/470781/ | amb_fremantle_day |
| lapping | Ocean-WavesLapping | rj13 | https://freesound.org/s/570955/ | amb_river_day, amb_river_night, amb_fremantle_night; place_quay, place_quay_night, place_riverside, place_riverside_night, place_jetty, place_jetty_night; traffic_ferry_wake_loop |
| ferry | boat engine small ferry bassy NYC, USA.flac | kyles | https://freesound.org/s/452924/ | amb_river_day; place_quay; traffic_ferry_engine_loop, traffic_ferry_idle_loop |
| freo_train | Railway Line & Signal Lights (freight train leaving Fremantle port) | dbache | https://freesound.org/s/351425/ | amb_fremantle_day |

Fully synthesised (no recordings): pedestrian-crossing signals (amb_ped_*),
sirens, Transperth train pass-bys, level-crossing bells, silver gulls, wind in
the gums, traffic pass-bys, air-con units, club bass, car stereo, engine idles,
ship horns, port clanks, all of `audio/oddity/` except the voices (below),
every car door, seatbelt, key and start-up sound, both 500e motor sets and
their pedestrian tones (the New 500e's is original, not the real car's
tune), the kerbside vans, taxis, trolley, hazards and ticket printer, the
phone notification, every bird call in `audio/field/` except the lorikeet, black cockatoo,
boobook and wagtail chatter cuts (above), the camera, binocular and journal
sounds, and all the fishing sounds.

## The cat and the midnight voices (`gen_home.py`, `gen_amb.py odd_`)

Licence for every row: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/).
The voices are played backwards and buried in radio static, so no words survive.

| Key | Title | Author | URL | Used in |
|---|---|---|---|---|
| cat_meow_x5 | Cat meowing x5 | peridactyloptrix | https://freesound.org/s/214759/ | home_cat_meow_01 |
| cat_chirp | cat chirp.wav | dreamstobecome | https://freesound.org/s/451250/ | home_cat_meow_02 |
| cat_wants_food | Cat Wants Food | Oneirophile | https://freesound.org/s/120160/ | home_cat_meow_03 |
| cat_purr | Cat Purring | Worldsday | https://freesound.org/s/449926/ | home_cat_purr |
| voice_reader | One-Word-At-A-Time: The Chaos Code / Chapter 1 (Read by: unfa) | unfa | https://freesound.org/s/231368/ | odd_midnight_station_01..03 |
| whisper_ind | indistinctwhispering.wav | BlueSiren | https://freesound.org/s/377743/ | odd_static_whisper_02, _04 |
| whisper_four | Four_Voices_Whispering.wav | geoneo0 | https://freesound.org/s/143902/ | odd_static_whisper_01..05 |

## Horns (`gen_car.py`, `gen_traffic.py`)

Licence for every row: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/).

| Key | Title | Author | URL | Used in |
|---|---|---|---|---|
| horn_wanaki | Car Horn_Irritated driver stuck in traffic.wav | wanaki | https://freesound.org/s/569613/ | car_horn_modern_tap, car_horn_modern_hold |
| horn_small | small horn.wav | tm1000 | https://freesound.org/s/94868/ | car_horn_classic_meep |
| horn_twin_hi | BusHorn_LAURENPOND.wav | LaurenPonder | https://freesound.org/s/635681/ | car_horn_abarth |
| horn_mito | boedie_alfa_romeo_MiTo_honking_car_horn.wav | boedie | https://freesound.org/s/457425/ | traffic_horn_car_01 |
| horn_fabia | Car Horn Skoda Fabia | innov8_Music | https://freesound.org/s/871628/ | traffic_horn_car_02 |
| horn_devern | Car Horn Honk.wav | DeVern | https://freesound.org/s/349922/ | traffic_horn_car_03 |
| horn_truck_air | powerfull horn | trezz77 | https://freesound.org/s/546528/ | traffic_horn_bus |
| horn_airhorn | airhorn-short.wav | guitarguy1985 | https://freesound.org/s/68999/ | traffic_train_horn |

## Thunder (`gen_weather.py`)

Licence for every row: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/).

| Key | Title | Author | URL | Used in |
|---|---|---|---|---|
| thunder_close1 | Lightning strike 2 | alexdarek | https://freesound.org/s/646912/ | weather_thunder_close_01 |
| thunder_close2 | Close lightning strike 2018 07 07 | csengeri | https://freesound.org/s/434359/ | weather_thunder_close_02 |
| thunder_close3 | Thunderstorm lightning strike | foad | https://freesound.org/s/243614/ | weather_thunder_close_03 |
| thunder_far1 | distant thunders meadow | Yuval | https://freesound.org/s/196125/ | weather_thunder_distant_01 |
| thunder_far2 | Thunder big | s-light | https://freesound.org/s/414050/ | weather_thunder_distant_02 |
| thunder_far3 | distant storm 1.WAV | Soojay | https://freesound.org/s/319568/ | weather_thunder_distant_03 |
