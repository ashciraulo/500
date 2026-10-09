# The field journal: birds and fish

The game has drifted into "Dredge on wheels", and this leans into it. Where
Dredge has a boat, a hold and a dock, we have a little car, a film roll and
an esky, and the photo lab and the tackle shop. Birds come first; fishing
follows on the same journal, money and gear.

## The loop

1. **Go out.** Drive somewhere with the right kind of place for what you want:
   Kings Park bush at dawn, the river at dusk, Herdsman Lake, a jetty at night.
2. **Notice the signs.** Like Dredge's bubbling water, a spot gives itself
   away: a little knot of birds wheeling over the trees, a flock lifting off a
   lawn, gulls working the water over a bait school. You can see these from
   the road, so you pull over.
3. **Look.** Stop the car (or get out) and raise the binoculars (B, or D-pad
   right). Find the bird, keep it in view a moment and it's identified: the
   journal now has it as *seen*.
4. **Get the shot / land the fish.** A short minigame (below). A good one puts
   a frame on the film roll or a fish in the esky.
5. **Come home to port.** The film roll and the esky are your hold. The roll
   has 24 frames to start with; the esky holds a few fish and its ice melts
   over the game hours, so a catch is worth more the sooner it's weighed in.
   Prints are developed and sold at the photo lab on Lake Street, Northbridge.
   Fish are weighed in at the tackle shop for the anglers' club prize money
   (WA doesn't let you sell a recreational catch, so the club pays instead).
6. **Upgrade.** Better binoculars see further and identify faster; camera
   bodies hold more frames and make the shot easier; long lenses reach shy
   birds; fast film works at night. Rods, reels, a crab net and bigger eskies
   for fishing. Some gear shows on the car (a rod on the roof rack).

   Lenses and film are on the lab counter next to the camera bodies. A 200 mm
   zoom ($380) makes a bird 1.6x bigger in the photo, a 500 mm mirror lens
   ($1250) 2.5x, so a far bird still makes a print, and shy birds stay calmer
   while you focus. ISO 100 film can't cope after dark: the dial narrows and a
   night shot comes out grainy (one star). ISO 800 ($160) copes with dusk and
   most of the night; ISO 3200 ($520) is sharp at midnight.
7. **Fill the journal.** Every species has a page: a silhouette and a hint
   ("Kings Park banksia, early morning") until you find it, then your best
   photo and grade, or your biggest fish.

No timers chase you, nothing fails hard. A bird you miss is still there
tomorrow, or another one is.

## Birds

Forty-two real Perth species, each tied to real places, times and weather:
magpies and ibis (the ones traffic already puts in the parks count too),
rainbow lorikeets in the city trees, black swans on the river and Lake Monger,
pelicans at Claisebrook Cove, Carnaby's black cockatoos coming in to Kings
Park at dusk, kookaburras at dawn, an osprey over Point Walter, tawny
frogmouths and boobooks only at night, rainbow bee-eaters arriving for the
spring. Common birds are everywhere; the rare ones need the right place, hour
and luck.

**Quiet places.** Ten spots nobody tells you about (the map's hidden
birding POIs): the Herdsman Lake reedbeds, Monger Island, the Perry Lakes
reeds, Floreat Lake, Kooyar Kep in Kings Park, the Heirisson Island marsh,
the Burswood Park lakes, the Alfred Cove flats, the East Fremantle reeds and
the Bibra Lake reeds on its north-east shore.
Nothing marks them on the map or in the journal. Walk within 60 m of one and
it goes in the back of the journal (and on the map). Three birds live only in
places like these: the Australian reed warbler in the reedbeds, the
buff-banded rail at muddy edges at first and last light, and black-winged
stilts on the flats. Two fishing spots are quiet too, the Point Walter
sandbar and the Trigg Island rocks: no bait bucket and no blank page until
you've stood there.

**The shot (Dredge's fishing minigame, as a camera).** Press Enter / A with a
bird in view. A dial appears round the viewfinder with one to three "sharp"
arcs and a needle sweeping round it, like the lens hunting for focus. Press
when the needle is in an arc. A few clean presses and the shutter fires.
Meanwhile the bird keeps moving, so keep it in the frame. Shy birds have
smaller arcs, a faster needle and less patience; a miss can flush them. The
grade (one to three stars) comes from how cleanly you hit and how well the
bird fills the frame. The photo is a real screenshot and goes in the album.

## Fish

Twenty-three real spots, placed on the map's own jetties, foreshores and
beaches by `tools/field/place_spots.gd` (`data/field/fishing_spots.json`):
the Mends Street and Coode Street jetties, Point Fraser, Heirisson Island,
Claisebrook Cove, the East Perth and Burswood jetties, the Maylands
foreshore, the Barrack Street Jetty at Elizabeth Quay, Canning Bridge,
Claremont, Freshwater Bay, Mosman Bay, the Point Walter jetty, East
Fremantle, the Fishing Boat Harbour, Fremantle harbour, the North Mole,
Leighton, the Cottesloe and City Beach groynes and Trigg Point. (Under the
Garratt Road bridge is in the data, but the map isn't built that far up the
river yet.) Sea spots only count the sea as water, not the hollows behind
the dunes. Walk within 30 m of one and it
goes in the journal; a bait bucket marks where to stand, and rings spread on
the water while something worth catching is about.

Fifteen catches (`data/field/fish.json`): blowies (everywhere, worthless),
black bream, tailor, herring, yellowfin and King George whiting, flathead,
tarwhine, skippy, garfish, squid under the lights at night, mulloway in the
deep holes after dark, pink snapper off the moles at night, blue manna crabs
in the crab net, and an old 500 hubcap from the 1970s somewhere off the Esplanade.
Each has real hours, water (river, estuary, ocean), spot tags it wants
(jetty pylons, flats, snags, deep, rocks, beach, lights), a real legal size,
a length range (mostly small ones, the odd big one), and a weight from
length (kg = k x (cm / 10)^3).

**The catch.** Walk to a spot and press F / A: the rod comes out (the walker
stands still; mouse or right stick still looks). Hold F to swing back and let
go to cast where you're looking: a longer swing, a longer cast (22 m, 28 m or
36 m by rod). Cast on land and it snags. Then the float: it nods when
something's having a look (strike at a nod and shy fish leave), and goes
under when it bites. Strike while it's under (1 s for a bold fish, 0.5 s for a
shy one) or it takes the bait.

The fight: hold F to reel, let go to give it line. Reeling raises the line
tension; letting go eases it and the fish takes line. Every few seconds the
fish makes a run (tension climbs two and a half times as fast); half a second
before, the rod tip shivers and the screen says so. Ease off through the run.
Tension at the top snaps the line; 70 m out and it's stripped the reel; no
tension at all for 2.5 s and a fish that fights throws the hook. Big fish tire
as you keep pressure on. Tuned so a bream or tailor lands on the old rod with
a little care, a 60 cm snapper wants patience, and a mulloway wants the surf
rod (the old rod can't hold one; the graphite rod can, if you heed every run).

Landed, it's held up in front of you with a card: size, weight, legal or not,
first in the journal, what the club would pay. Keep it (F), let it go (R) or
photograph it (C; the photo goes in the album and on its journal page).
Undersized fish and blowies can't be kept; the hubcap goes home, and from
then on it hangs on the outside of the shed door (chrome out; M.'s own
hubcap is on the wall inside).

**The esky and the tackle shop.** Kept fish go in the esky (4, 8 or 14). The
bait and tackle shop at the end of Mends Street, South Perth, on the jetty
forecourt (pull into its bay, or walk in to the counter) weighs them in for
the anglers' club's prize money: kilos x the species' rate, with a bonus the
first time a species goes on the board. The best fish of the weigh-in stays on
the scale's tray, and your biggest of each species is pinned to the brag
board behind the counter (your photo if you took one).
Fish go soft out of the ice: a bag ($5) keeps the esky cold for 8 game hours;
after that a fish loses value over 4 hours, down to 40%. The shop sells the
graphite rod ($380), the surf rod and Alvey reel ($1100), the family and chest
eskies ($160, $420) and a crab net ($45).

**The crab net.** At a spot tagged for crabs, getting the rod out drops the
net over the side too. Come back after 45 game minutes or more (longer, and at
night, does better) and F pulls it: a few blue mannas, the legal ones (12.7 cm
across the shell) into the esky. One net, so it's either down or with you.

## After midnight

Dredge's aberrations, our way: a few birds after midnight are subtly wrong.
They show up in step with the main mystery (one more after each clue you
find), and each one already has a page in the journal, written in 1979 by
"M.", the tenant who made the NIGHT DRIVE tapes. The binoculars you start
with were on the hook by the back door, with an M scratched into them.

- A tawny frogmouth on the pole outside 15 Little Shenton Lane whose head
  follows the car.
- A magpie in Russell Square carolling at 2 am, and the tune is the midnight
  station's.
- A black swan off Riverside Drive facing upstream, perfectly still, where
  the river lights rise.
- Thirteen black cockatoos in Kings Park at 3 am. Always thirteen.
- An ibis standing in the middle of the Barrack Street crossing; the lights
  change when it lifts its head.
- A boobook in Kings Park, looking out of the hollow of a dead marri stump.
  The nest inside is lined with brown cassette tape, and a scrap of a
  NIGHT DRIVE label is caught on a twig.
- Once the shed is open: a small grey bird on the shed roof that isn't in any
  field guide. Its page is already filled in, in your handwriting.

The lab won't sell prints of these ("they've come out blank, love"), but they
stay in the journal and the album. Each one you find also puts M.'s torn-out
page for it up on the wall by the back door, pinned in a loose column above
the coat hooks where his binoculars hung (the grey bird's page is in your
blue biro, with a blue pin). Fishing has two of its own, which can't
be kept and whose pages in the Fish tab are M.'s:

- A black bream with a yellow 1979 fisheries dart tag in its jaw, at the
  Mends Street jetty after midnight once the ticket's found.
- A big pale flathead with a cold green light coming off it, on the flats at
  Point Fraser between midnight and 3:30 am once the atlas page is found.
  Let it go and its light shows under the surface, drifting out and fading.

**Flickering.** Once the late city starts (`docs/STORY.md`), the wrong
birds flicker: blink out with a faint tape shimmer and a soft warble, then
back a moment later, up to a metre from where they were. In act 2 only the
frogmouth does it, and only through the binoculars; from act 3 all of them,
and the focus dial jumps if one blinks mid-shot; from act 4 ordinary birds
too, now and then, where the late city is strong; and in act 5 the thirteen
cockatoos lift off and fly beside the car on Fraser Avenue after 2 am,
flickering all at once. "Strange things: gentle" keeps the shimmer but
leaves them where they were. The journal gets a third bookmark, Nights, the
first time the late city gives you something to write down.

**Blank prints.** From act 3 the wrong birds' prints come back blank, and
Ros holds each one up to the light: it's a page for the night section of the
1979 field guide Mick never finished. Give it to her, or keep it. Keep one
and the next morning there's an envelope of cash inside the front door, with
a note in the tapes' handwriting ("For the bird on the pole. More welcome.").
After that the lab shows what the buyer will pay. The thirteen's print is the
story's second choice: the guide's last night page, or $5,000. In the
journal, their pages say you saw them "sort of", and whether Ros or the
buyer has the print. City of Light leaves them ordinary birds; Lights Out
fades their pages to blank over a week.

**The photograph.** Some time in act 3, driving along, a shutter clicks
behind you. Nobody's there. The next roll comes back with one frame you
didn't take: you at the wheel, from the back seat, the date stamp in the
corner reading '79 7 11. Ros says she'll keep it, if you like; or it goes
home in the album.

## Progression, lightly

Selling prints and weighing in fish earns money, so it's an alternative to
deliveries. Journal stats (`species_seen`, `species_photographed`,
`prints_sold`, `fish_caught`, `fish_species`) are known to Progression, so the
career can ask for a few. Milestones give cosmetics: a nodding willie
wagtail on the dash at 10 species, a field-guide sticker at 20 (both the
car's side, `dash_bird.glb`), and at 30 a feeder in the townhouse courtyard
(`Feeder_Spot`) that brings garden birds you've seen home by day.

**At home.** A new game starts with the binoculars on the coat hook by the
sliding door (`Binoculars_Hook`); F takes them, and B works from then on.

## Building it (batches)

1. **Birds core:** data, journal and save, sightings in the world,
   binoculars, the shot, the photo lab (develop, sell), the journal screen (J).
2. **Gear and the night birds:** the lab's camera counter, upgrades, the
   wrong birds and M.'s pages.
3. **Fishing:** spots, the cast and reel, esky and ice, the tackle shop, the
   crab net, the journal's Fish tab. (Done.)
4. **Sound and polish:** calls per species from the audio thread, cosmetics,
   career challenges with the driving thread.

## Hooks (for other threads)

See the field journal section of `docs/HOOKS.md`.
