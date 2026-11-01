# Dockside Sort: Cargo Puzzle

Greybox, portrait, one-thumb colour-sort. No lives, no energy, no ads, and no shop. Coins are a balance only.

## Setup decisions

- Engine: Godot 4.7.2 stable (latest stable 4.x on 1 Nov 2026), GDScript. Pinned in `ci/versions.env` with the matching export templates.
- Repo: https://github.com/tscook93-dev/dockside-sort
- Play-testing uses both:
  - a single-threaded web build (no SharedArrayBuffer, no cross-origin isolation) opened on a phone
  - an arm64 Android debug APK (CI debug keystore, not a store key)
- Art is greybox. The camera is a fixed orthographic board. Each colour is a hue plus a shape: coral circle, teal square, gold triangle.
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

The game opens on the ship list. Desktop keys: `1` `2` `3` start an unlocked level, `S` opens settings. On a level, `1` `2` `3` select columns, `Q` `W` `E` place on stacks, `H` hold, `U` undo, `R` restart, `L` returns to the list, Space confirms the prompt.

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

Colours: `coral`, `teal`, `gold`.

## Milestones

- [x] M1 Core sort mechanic (greybox; deck grid, colour stacks, 1 hold slot, undo, win, soft fail + free restart, 2-3 hand-made test levels) — done, pending Tobias's merge of #1
- [ ] M2 Level flow (level progression, 3-star scoring, coin payout, local save, restart, settings shell) — in progress
- [ ] M3 First levels (levels 1-30 + FTUE with every mechanic in the brief's levels table)
- [ ] M4 Art pass (chunky 2.5D, port yard hub chapter 1, daily dock challenge + login streak)
- [ ] M5 Monetisation hooks (rewarded, interstitial rules, No Forced Ads, coin packs S/M/L; test/sandbox IDs only)
- [ ] M6 Analytics (the brief's event list behind one thin wrapper; debug sink first)
- [ ] M7 Soft-launch build (release signing, compliance checklist, crash tooling, Philippines release candidate)

The brief groups the same work as three milestones (playable prototype, content-complete, soft-launch). This checklist is the engineering split for the repo. M1 here is the brief's playable prototype, narrowed to the colour-stack loop.

## Open design questions

These are the readings used where the brief does not specify the board. They match a classic colour-sort (only the top of a pile moves, and a stack accepts the same colour or starts empty).

1. **Legal order.** A stack accepts a container only when it is under capacity and either empty or its top container is the same colour. There is no order inside a colour. A different colour cannot be buried on top.
2. **Deck.** The deck is a grid of columns. Only the top container of a column can move. Containers underneath stay put until the ones above leave. M1 does not place containers back onto deck cells. "Cannot place into occupied cells" is enforced on the only drop targets: a full stack rejects, a wrong colour rejects, and the hold rejects a second container.
3. **Shipping.** When a stack reaches `capacity` it ships immediately: those containers leave play and the stack slot is empty again. Because mixed colours are illegal, a full stack is always one colour. Each test level has exactly `capacity` containers of each colour, so one shipment clears that colour.
4. **Open versus pinned stacks.** An empty open stack accepts any colour, and that colour sticks until it ships. Level 1 pins one stack per colour so the tutorial cannot soft-fail. Levels 2 and 3 use two open stacks. Pinning is level data, not a colour-gate.
5. **Hold.** One container. It can come from a column top and leave onto a legal stack. It cannot move back onto the deck.
6. **Win.** The deck, the hold, and every stack are empty. Everything has shipped.
7. **Soft fail.** Shown when the position is not a win and no legal move remains. With one hold, that is the brief's case: the hold is full and nothing can stack. The prompt offers Undo and Restart, both free and immediate. Restart is also always on the board. Nothing is behind a timer, an ad, or a coin.
8. **Undo.** Every successful move is snapshotted, including ships. History keeps 40 snapshots, which is at least the required 10. All undos are free in M1. A rejected tap is not a move and is not recorded.
9. **Input.** Tap to select, tap to place. No drag in M1.
10. **Length.** These three levels are short so the loop can be proved in one sitting. The 2–3 minute target is for later authored levels, not these.
11. **Stars.** 3 stars means the clear used at most `undo_limit` undos and the temporary hold slot was not used. 2 stars is a light assist: undos may run up to `undo_limit + 2`, and using the temporary slot (not built yet; the flag stays false) also stops a clear at 2 stars while it is still inside that undo band. Any other clear is 1 star. The saved star count for a level is the best, not the latest.
12. **Coins.** A clear pays 10 coins for each star that is new for that level. Replaying a 3-star clear pays 0. Improving a 1-star clear to 3 stars pays 20. There is no shop. The win screen shows the stars, the coins just earned, and the balance.
13. **Unlocks.** Level 1 starts unlocked. Clearing a level unlocks the next one in list order. Locked rows stay on the list and do not start. Leaving mid-level from the Levels button records nothing.
14. **Save.** Progress, best stars, the coin balance, and the sound and haptics toggles are written to `user://progress.cfg` (app storage on Android and desktop). On web the same snapshot is also written to `localStorage`, because the browser file sync is asynchronous and a reload can beat it. A reload reads that save back.
15. **Settings shell.** Sound and haptics are stored toggles. There is no music yet. Haptics calls a short vibration when a stack ships, which does nothing on web. Privacy, restore purchases, and support are rows that only say they are not in this build.

Not in this build, on purpose: ads, a second hold, the temporary slot purchase, locked containers, double-high stacks, conveyors, glass, colour gates, accounts, and a shop.

## Brief versus design doc

The design doc wins where they disagree. None of these change M1.

- **When later mechanics first appear.** The design doc's table is the unlock: double-high at 12, fragile glass at 24, colour gate at 30, and colour stacks may use 3–4 colours from level 1. The brief's levels 1–30 table teaches double-high at 13–15, glass at 21–23, the colour gate at 27–29 (level 30 is a boss mix), and holds the fourth colour to levels 11–12. Later content should follow the design doc's unlock levels. The brief's table is still the more detailed 1–30 lesson plan and should be reconciled when those levels are written.
- **How many port chapters ship.** The design doc's MVP list includes three chapters (Sydney, Singapore, Rotterdam). The brief's must-have is one chapter (Sydney), with chapters 2–3 only if they fit. The design doc wins: three chapters are in the product, not in M1.
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
