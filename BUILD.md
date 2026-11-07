# Dockside Sort: Cargo Puzzle

Greybox, portrait, one-thumb colour-sort. No lives, no energy, no ads, and no shop. Coins are a balance only.

## Setup decisions

- Engine: Godot 4.7.2 stable (latest stable 4.x on 1 Nov 2026), GDScript. Pinned in `ci/versions.env` with the matching export templates.
- Repo: https://github.com/tscook93-dev/dockside-sort
- Play-testing uses both:
  - a single-threaded web build (no SharedArrayBuffer, no cross-origin isolation) opened on a phone
  - an arm64 Android debug APK (CI debug keystore, not a store key)
- Art is a chunky 2.5D toy harbour: extruded blocks, bold outlines, one fixed view. Each colour keeps its hue plus a shape: coral circle, teal square, gold triangle, indigo diamond.
- Portrait layout, controls along the bottom, tap targets at least ~108 px on a 720-wide board (about 54 dp on a 360 dp-wide phone, and they grow on taller screens). A minimum safe margin is always applied, and any inset reported by the display is added on top.

## Design sources

- Build brief: https://cursor.com/canvas/store-1a4ece05-3f90-4d81-86ca-7469d9455135/71c4f0fa-d83d-434a-8dda-f2c2c86de9b0
- Game design doc: https://cursor.com/canvas/store-1a4ece05-3f90-4d81-86ca-7469d9455135/f3da1fab-afce-4c34-b3ca-1073f6bf2f6c

If the brief and the design doc disagree, the design doc's decisions log wins. Conflicts that matter later are listed at the bottom. They do not change this milestone: M1 only implements colour stacks, one hold, undo, win, and soft fail.

## How to build and run

Install Godot 4.7.2 and the 4.7.2 export templates (the same URLs and checksums as `ci/versions.env`). From the repo root:

```bash
godot --headless --path . --import --quit
godot --headless --path . --audio-driver Dummy -s res://tests/rules_check.gd
```

Web export (single-threaded; the preset sets `variant/thread_support=false`):

```bash
mkdir -p build/web
godot --headless --path . --audio-driver Dummy --export-release "Web" "$PWD/build/web/index.html"
python3 -m http.server 8765 --directory build/web
```

Open `http://127.0.0.1:8765/` . The exported page sets `GODOT_THREADS_ENABLED = false`, so GitHub Pages and mobile Safari/Chrome do not need special headers.

Android debug APK (arm64 only):

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT="$HOME/android-sdk"
bash ci/configure_android.sh
mkdir -p build/android
godot --headless --path . --audio-driver Dummy --export-debug "Android" "$PWD/build/android/dockside-sort-debug.apk"
```

`ci/configure_android.sh` unzips the official Android build template (it is not committed), writes `android/.build_version`, and generates the well-known debug keystore if needed. The SDK needs `platforms;android-36` and `build-tools;36.1.0`, which is what Godot 4.7.2's template compiles against. No NDK is required for this prebuilt template.

GitHub Actions (`.github/workflows/playtest.yml`) does the same steps on every push except to `gh-pages`. It publishes:

- the web build on the `gh-pages` branch, at `/pr-<number>/` for a pull request and at the site root for `main`
- the debug APK as a public prerelease asset (`pr-<number>` or `main-debug`), which a phone can download without a GitHub login

Workflow artifacts are also uploaded, as a fallback that does require a GitHub login.

### How to play

Tap the bright top container of a column, then tap a stack or the hold. A stack only takes its own colour. On level 1 the three stacks are pinned (Coral, Teal, Gold). On levels 2 and 3 an empty stack accepts any colour, and it ships when it holds 3 of that colour. Undo and Restart are free.

The game opens on the Sydney port. Play continues the earliest unlocked ship that has no stars. Ships opens the list of all 30. A locked row stays locked until the ship before it is cleared, and an existing save is kept. Drag the list to move it. Port returns to Sydney. Desktop keys: on the port, Enter plays and `L` opens ships; on the list, `1`–`9` start an unlocked level. On a level, `1`–`9` select columns, `Q` `W` `E` `A` place on stacks, `H` is hold 1, `J` is hold 2 when it is open, `U` undo, `R` restart, `L` returns to the port. Days on the port change at 00:00 UTC.

## Levels

Drop another `levels/level_XX.json` in and the next export picks it up (`include_filter` is `levels/*.json`). Names sort, so zero-pad them (`level_04.json`, not `level_4.json`).

```json
{
  "id": 4,
  "title": "Name",
  "blurb": "One line under the title.",
  "capacity": 3,
  "berths": ["", ""],
  "columns": [
    ["coral", "teal", "gold"]
  ]
}
```

- `columns` run left to right. Each column is top-first: index 0 is the only container that can move.
- `berths` is one entry per stack. `""` is an open stack. A colour name pins that stack to the colour.
- `capacity` is how many matching containers ship the stack off the board.
- `undo_limit` is N for 3 stars. Omit it and N is 0.
- A column entry may be `key` or `locked:coral` (also teal, gold, indigo). `double_high` is a list of column indexes that start two containers tall.

Colours: `coral` circle, `teal` square, `gold` triangle, `indigo` diamond.

## Milestones

- [x] M1 Core sort mechanic (greybox; deck grid, colour stacks, 1 hold slot, undo, win, soft fail + free restart, 2-3 hand-made test levels) — done, pending Tobias's merge of #1
- [x] M2 Level flow (level progression, 3-star scoring, coin payout, local save, restart, settings shell) — done, pending Tobias's merge of #2
- [x] M3a First levels, part 1 (levels 1–17, FTUE, locked container + key, 4th colour, double-high; readability fixes) — merged in #3
- [x] M3b Levels 18–30 with the mechanics already in the game — merged in #4
- [x] M4 Sydney hub, chunky 2.5D kit, second permanent hold, UTC daily dock, 7-day streak and one freeze token — merged in #5
- [ ] M5 Simulated monetisation, approved for local testing only. No store SDK, no ad SDK, and not a release build
- [ ] M6 Analytics (the brief's event list behind one thin wrapper; debug sink first)
- [ ] M7 Soft-launch build (release signing, compliance checklist, crash tooling, Philippines release candidate)

The brief groups the same work as three milestones (playable prototype, content-complete, soft-launch). This checklist is the engineering split for the repo. M1 here is the brief's playable prototype, narrowed to the colour-stack loop.

## Design answers (Playtester, 1 Nov 2026)

1. **Legal order.** Same colour only. A stack accepts a container when it is empty or its top is the same colour, and it is under capacity. The only extra ordering rule is double-high, from level 13: the top container of that pile moves before the bottom one.
2. **Stack capacity.** `capacity` is per level and is 3 or 4. Levels 1–19 use 3. Some levels from 20 may use 4.
3. **Pinned and open stacks.** Each stack is pinned to a colour or open. Levels 1–2 are pinned Coral, Teal, and Gold. From level 3, open stacks are the norm. Later levels may mix pinned and open stacks. A stack still never holds two colours at once.
4. **Deck.** Columns, top-only moves, and nothing goes back onto the deck.
5. **Hold.** One container per slot. It leaves only onto a legal stack.
6. **Input.** Tap, then tap, is the primary input. Drag comes later and is not built.
7. **Stars.** The current star rule stands. 3 stars means at most `undo_limit` undos and no temporary slot. 2 stars is a light assist (up to two undos past that limit, and a temporary slot also caps the clear at 2 stars inside that band). Any other clear is 1 star. 10 coins per star is a tunable constant (`COINS_PER_STAR`).
8. **Replay coins.** A replay pays 10 coins only for each star that level had not already earned. Replaying a 3-star level pays 0.
9. **Level schedule.** The 1 Nov brief table still describes the intended mechanic intros: 1–2 colour stacks, 3–4 hold, 5–7 practice, 8–10 key, 11–12 fourth colour, 13–15 double-high, 16–17 locked plus double-high, then conveyor, glass, and colour gate. On 7 Nov 2026 Tobias approved a playtest batch that uses only mechanics already implemented for levels 18–30, and defers conveyor, glass, and colour gates until after he plays this build. That amendment covers this batch only. It is not a claim that the original Philippines soft-launch content is complete.
10. **Chapters.** Sydney is the only chapter for the Philippines soft launch.
11. **Hold slots.** Level 3 introduces the hold with one slot. A second permanent slot is a later coin upgrade in the port, after about level 15, capped at 2. The temporary +1 slot arrives with monetisation. Every level must be solvable with one hold slot and no assists.

## Open design questions

What is still an implementation choice, not a Playtester answer:

1. **Shipping.** A stack ships and clears when it reaches `capacity`. Mixed colours cannot be stacked, so a full stack is one colour. Each colour's count in a level is a multiple of `capacity`.
2. **Win.** The deck, the hold, and every stack are empty.
3. **Soft fail.** Shown when nothing legal remains. Undo and Restart are free and immediate. Restart is always on the board.
4. **Undo memory.** History keeps 40 snapshots. A rejected tap is not recorded.
5. **Save.** `user://progress.cfg` on Android and desktop. Web also writes `localStorage` so a reload cannot outrun the browser file sync.
6. **Settings.** Sound and haptics are stored toggles. There is no music yet. Shipping a stack requests a short vibration when haptics are on. Privacy, restore purchases, and support only say they are not in this build.
7. **Key.** A `key` token sits on the deck. Tap it when it is the top of its column and it is collected: it does not enter a stack or the hold. A `locked:colour` container cannot move while any key remains on the deck. One key unlocks every lock on that level.
8. **Double-high.** `double_high` lists column indexes that start exactly two containers tall. They use the normal top-then-bottom rule and are drawn with a "2-high" label.
9. **Fourth colour.** `indigo`, drawn as a diamond.
10. **FTUE.** Levels 1–4 show one short coach line at a time (tap a container, tap a stack, use the hold, use undo). Skip dismisses it, and the save remembers that the level's coach was finished.

## 7 Nov 2026 playtest amendment

Tobias approved the next playtest as levels 18–30 using only rules already in the build: colour stacks, the four colours, key and lock, double-high, one hold, capacity 3, and capacity 4 from level 20. Conveyor, fragile glass, and colour gates are deferred until after that playtest. The solver only checks that a level can be cleared with one hold and no undo. It does not judge whether a layout is fun or the right difficulty.

## M4 rules approved 7 Nov 2026

Tobias approved this package for the current branch. It is not a store release. The device clock is UTC. The label on the port says 00:00 UTC. There is no server and no Melbourne offset. A backward clock cannot open a new daily or streak claim. A forward clock is accepted and is not policed. Saves stay in the existing `user://progress.cfg` and web `localStorage` key. Old saves keep their coins, stars, and unlocks.

- **Second hold.** The offer appears after the first clear of level 15, including a save that already has stars on level 15. One purchase costs 300 coins and opens a second permanent hold. It cannot be bought twice. Fewer than 300 coins changes nothing. The cap is two permanent holds. This is not the temporary slot, and using it does not change the star rule. Every level is still solvable with one hold and no assist.
- **Daily dock.** It opens after level 5 has been cleared. The layout is an existing main level. The UTC day number, `floor(unix UTC seconds / 86400) mod 7`, picks it: 0 level 18, 1 level 19, 2 level 20, 3 level 21, 4 level 22, 5 level 23, 6 level 24. The first clear of that UTC day pays 30 coins. The same day pays 0 after a replay or a reload. It does not change main stars, the first-clear coin payout, or which ship is unlocked. The port shows when today is already done.
- **Streak.** The first visit to the port on a UTC day credits once: 10, 10, 15, 15, 20, 20, 30. The day after day 7 starts again at day 1. There is no second claim button. A miss of one UTC day with no freeze token makes the next credit day 1. Coins already owned stay. Day 7 grants one freeze token, and the cap is 1. Coming back after exactly one missed day spends that token and continues the next streak step. Two or more missed days reset the next credit to day 1 and keep the token. Missed days pay nothing.

## M5 simulated test package, approved 7 Nov 2026

Tobias approved these values for simulated local testing only. They are not production prices. Settings says "Local test" and "not a checkout." There is no ad SDK and no store SDK. Cancel, failure, unavailable, a repeated callback, and a callback from another level grant nothing. A purchase is stored once per transaction. Restore puts back No forced ads and does not pay pack coins again. The coin balance never goes negative.

- **Undo.** Each attempt has 3 free successful undos, separate from the star limit. After that, a successful undo costs 50 coins, or one completed simulated reward does one undo immediately. An empty history does not offer or debit. Restart resets the 3 free undos. Undo does not refund coins or remove the extra hold. History still keeps 40 moves.
- **Extra hold.** 100 coins, or one completed simulated reward, adds one hold for the current unfinished level. It stays through restart and leaving the app, and it clears when the level is finished or another ship is opened. It cannot be bought again while it is active. It still caps that clear at 2 stars. Restart stays free.
- **Double coins.** Only a main clear that paid for newly earned stars can be doubled, once, by a completed simulated reward. The bonus equals that payout, not the wallet. A replay with no new stars, a daily clear, and streak or pack coins are not doubled.
- **Simulated packs.** S is 500 coins at USD 1.99 / AUD 2.99. M is 1500 at USD 4.99 / AUD 7.99. L is 3500 at USD 9.99 / AUD 14.99. Simulated No forced ads is USD 9.99 / AUD 14.99. It turns off the simulated interstitial. Rewarded tests stay available.
- **Simulated interstitial.** After the first clear of level 10, which itself shows nothing and starts the count at 0, every third later main clear can show one. It is skipped on a fail, restart, daily, open, exit, or during a puzzle. It needs 90 seconds since any simulated ad, including a rewarded one. No forced ads suppresses it. The count still resets, and a skipped one is not saved for later. It appears before the results. The results screen does not show a second one.

## Still not in this build

A real ad network, a real store, production product IDs, conveyor, glass, colour gates, accounts, and analytics. No store listing or device sign-off. A phone clock set forward can collect streak and daily rewards early; that is a known prototype limit.

## Still not in this build

A real ad network, a real store, production product IDs, the temporary hold's price and cap, conveyor, glass, colour gates, accounts, and analytics. No store listing or device sign-off. A phone clock set forward can collect streak and daily rewards early; that is a known prototype limit.

## Release gates still open

These are unchanged and not done: playable path smoke-tested on a mid-range Android phone and a recent iPhone, analytics end to end, ads and IAP in the soft-launch rules, crash rate and cold start, store listing and privacy flows, trademark and store-name check. This batch does not close them.

## Workflow

Headless `tests/rules_check.gd` and `tests/solve_levels.gd`, then the existing playtest workflow exports one single-threaded web build and one arm64 debug APK. No extra content framework.

## Brief versus design doc

The design doc wins where they disagree. None of these change M1.

- **When later mechanics first appear.** The design doc's table unlocks double-high at 12, glass at 24, and the colour gate at 30. The brief's levels 1–30 table is more specific. Playtester, 1 Nov 2026, chose the brief's schedule (see Design answers).
- **How many port chapters ship.** The design doc's MVP list includes three chapters. The brief's must-have is Sydney, with the others if they fit. Playtester, 1 Nov 2026: Sydney is the only chapter for the Philippines soft launch.
- **Coin Pack XL.** The design doc proposes an XL pack ($19.99 / $29.99). The brief's v1 table, and M5 above, stop at S/M/L. XL is labelled a proposal, not a locked decision. M5 stays S/M/L unless that proposal is locked.
- **Colour-blind glyphs.** The brief lists icon glyphs as a "should". The design doc's art direction requires an outline plus a glyph, and so does the locked art note for this repo. Glyphs are in the greybox.
- **Second hold.** The brief unlocks a permanent second slot from port progression. The design doc's mechanic table introduces hold slots (1–2) at level 3, and the port meta can also add a capped permanent slot. Those can be the same feature. M1 has one slot.

## What still needs a person

GitHub Pages does not turn itself on for a new repository. If the playtest site 404s after Actions goes green:

1. Open the repo on GitHub, then Settings, then Pages.
2. Build and deployment: Deploy from a branch.
3. Branch `gh-pages`, folder `/ (root)`, then Save.

If the workflow cannot push `gh-pages` or the prerelease:

1. Settings, then Actions, then General, then Workflow permissions.
2. Choose Read and write permissions, then Save.

On the phone, the APK install needs "install unknown apps" for the browser. The APK is debug-signed and is not a Play Store build.
