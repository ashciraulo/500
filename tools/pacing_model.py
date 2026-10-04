#!/usr/bin/env python3
"""Rough pacing model for the career: how many hours each tier takes.

Run it after changing data/progression/tiers.json, car prices in
data/cars/cars.json, or delivery pay in scripts/autoload/jobs.gd:

    python3 tools/pacing_model.py

It simulates an "average" player hour by hour using the assumptions below and
prints when each challenge and tier is done and when the next car is
affordable. It's a sanity check, not a promise: replace the assumptions with
play-testing numbers as they come in.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- Assumptions (per hour of play) -----------------------------------------
JOB_SHARE = 0.5          # share of play time spent on deliveries
TRIAL_SHARE = 0.08       # share spent on time trials
DRIVING_SHARE = 0.85     # share of play time the car is moving at all
AVG_SPEED_KMH = 30.0     # city average including lights and stops
DELIVERY_KM = 4.0        # average road distance of a delivery
DEADHEAD_KM = 2.5        # driving to the pickup
LOAD_MIN = 1.5           # pulling up, loading, unloading
QUICK_RATE = 0.5         # deliveries that earn the 25% quick bonus
FRAGILE_RATE = 0.3       # deliveries that are fragile (pay 30% more)
FRAGILE_PERFECT = 0.6    # fragile loads delivered without a scratch
NIGHT_RATE = 0.35        # deliveries done after dark
RAIN_RATE = 0.2          # deliveries taken in light rain (+25%)
STORM_RATE = 0.06        # deliveries taken in a storm (+50%)
CLEAN_RATE = 0.4         # deliveries in a clean car (5% tip)
TRIAL_MIN = 8.0          # one trial attempt including getting to the start
TRIAL_COUNT = 20         # named trials on the map (per car class)
PLACES = 60              # discoverable places on the map
PLACE_HALF_LIFE_H = 10.0 # hours to find half of the places
SUBURBS = 24             # suburbs with drop-offs
BADGES = 60              # hidden 500 badges
BADGE_HALF_LIFE_H = 25.0 # hours to stumble on half of them
PARTS_SHARE = 0.25       # share of income spent on parts, paint, washes
AVG_PART_PRICE = 600     # what a typical upgrade costs
FUEL_PER_KM = 0.27       # dollars of fuel per km (7 L/100 km x2 scale, $1.90/L)
BUYS_TIER_CAR_AT = 1.0   # buys the cheapest car of a new tier as soon as affordable


def _jobs_const(name):
    src = open(os.path.join(ROOT, "scripts/autoload/jobs.gd")).read()
    return float(re.search(r"const %s := ([0-9.]+)" % name, src).group(1))


BASE_PAY = _jobs_const("DELIVERY_BASE_PAY")
PAY_PER_KM = _jobs_const("DELIVERY_PAY_PER_KM")


def delivery_pay(multiplier):
    base = (BASE_PAY + DELIVERY_KM * PAY_PER_KM) * multiplier
    base *= 1.0 + FRAGILE_RATE * 0.3
    bonus = 0.25 * QUICK_RATE + 0.05 * CLEAN_RATE + 0.25 * RAIN_RATE + 0.5 * STORM_RATE
    return base * (1.0 + bonus)


def main():
    tiers = json.load(open(os.path.join(ROOT, "data/progression/tiers.json")))["tiers"]
    cars = json.load(open(os.path.join(ROOT, "data/cars/cars.json")))["cars"]
    medal_rewards = {"gold": 220, "silver": 120, "bronze": 60}

    minutes_per_delivery = (DELIVERY_KM + DEADHEAD_KM) / AVG_SPEED_KMH * 60 + LOAD_MIN
    stats = {k: 0.0 for k in [
        "deliveries", "night_deliveries", "rain_deliveries", "storm_deliveries",
        "fragile_perfect", "km_driven", "km_tier_car", "earned", "trials_medalled",
        "trials_silver", "trials_gold", "discoveries", "suburbs_delivered",
        "upgrades_fitted", "cars_owned", "washes", "badges"]}
    stats["cars_owned"] = 1
    money = 400.0
    tier = 0
    done = set()
    trial_attempts = 0.0
    car_tier = 0
    parts_spend = 0.0
    print(f"Minutes per delivery: {minutes_per_delivery:.1f}, pay at x1: ${delivery_pay(1):.0f}")
    step = 0.1
    hour = 0.0
    while hour < 120 and tier < len(tiers):
        hour += step
        mult = tiers[tier]["pay_multiplier"]
        dels = JOB_SHARE * 60 / minutes_per_delivery * step
        pay = dels * delivery_pay(mult)
        # Better cars medal more often.
        trial_attempts += TRIAL_SHARE * 60 / TRIAL_MIN * step
        skill = 1.0 + 0.35 * car_tier
        medalled = min(TRIAL_COUNT, trial_attempts * 0.6)
        silver = min(TRIAL_COUNT, trial_attempts * 0.3 * skill)
        gold = min(TRIAL_COUNT, trial_attempts * 0.1 * skill)
        trial_pay = 0.0
        for key, new, reward in [("trials_medalled", medalled, 60), ("trials_silver", silver, 60), ("trials_gold", gold, 100)]:
            trial_pay += max(0.0, new - stats[key]) * reward * mult
            stats[key] = max(stats[key], new)
        km = DRIVING_SHARE * AVG_SPEED_KMH * step
        stats["deliveries"] += dels
        stats["night_deliveries"] += dels * NIGHT_RATE
        stats["rain_deliveries"] += dels * (RAIN_RATE + STORM_RATE)
        stats["storm_deliveries"] += dels * STORM_RATE
        stats["fragile_perfect"] += dels * FRAGILE_RATE * FRAGILE_PERFECT
        stats["km_driven"] += km
        stats["km_tier_car"] += km if car_tier == tier else 0.0
        stats["earned"] += pay + trial_pay
        stats["discoveries"] = PLACES * (1 - 0.5 ** (hour / PLACE_HALF_LIFE_H))
        stats["badges"] = BADGES * (1 - 0.5 ** (hour / BADGE_HALF_LIFE_H))
        stats["suburbs_delivered"] = SUBURBS * (1 - (1 - 1 / SUBURBS) ** stats["deliveries"])
        stats["washes"] += step * 0.25
        money += (pay + trial_pay) * (1 - PARTS_SHARE) - km * FUEL_PER_KM
        parts_spend += (pay + trial_pay) * PARTS_SHARE
        stats["upgrades_fitted"] = min(9, parts_spend / AVG_PART_PRICE)
        # Buy the cheapest car of the newest tier once affordable.
        if car_tier < tier:
            options = sorted([c for c in cars if c["unlock"] == "tier" and c["tier"] == tier], key=lambda c: c["price"])
            if options and money >= options[0]["price"]:
                money -= options[0]["price"]
                car_tier = tier
                stats["cars_owned"] += 1
                stats["km_tier_car"] = 0.0
                stats["upgrades_fitted"] = 0
                parts_spend = 0.0
                print(f"  {hour:5.1f} h  buys {options[0]['name']} (${options[0]['price']:,})")
        current = tiers[tier]
        for ch in current["challenges"]:
            if ch["id"] not in done and stats[ch["stat"]] >= ch["target"]:
                done.add(ch["id"])
                print(f"  {hour:5.1f} h  {ch['title']}")
        if all(ch["id"] in done for ch in current["challenges"]):
            print(f"{hour:5.1f} h  TIER {tier + 1} DONE: {current['title']}  (money ${money:,.0f}, {stats['km_driven']:,.0f} km)")
            tier += 1
            stats["km_tier_car"] = 0.0
    if tier < len(tiers):
        missing = [ch["title"] for ch in tiers[tier]["challenges"] if ch["id"] not in done]
        print(f"Stopped at {hour:.0f} h in tier {tier + 1}; still to do: {', '.join(missing)}")


if __name__ == "__main__":
    main()
