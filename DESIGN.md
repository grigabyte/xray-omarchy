# Design

What the panel looks like and why. Carried over from the earlier panel where the rule
still applies; the reason is the rule.

## Icons

- `components/ActionIcon.qml` is the whole set: Canvas paths on a 16-unit
  grid, `strokeScale: 1.4`, each glyph one short path string in its `paths`
  table. A new glyph is a new entry there, never a new component. Drawn, not rasterised (Qt smears SVG at 12–16px) and not a text
  glyph (`×` is a multiplication sign and reads half-size).
- `components/XrayIcon.qml` is the brand mark, outside the set: a flat-capped
  bolt, crossed by a backslash with a cut-out gap when the tunnel is off, an
  urgent disc with a punched-out "!" on failure and whenever the CLI's
  verdict is not "protected" while the tunnel is meant to run (state
  `unprotected`: not routed, the killswitch or DNS off, or systemd starting
  the unit again after `net up` failed). The plain bolt means protected, never
  just "the core runs". While `on` is in flight the state stays `starting`
  until the CLI says protected, so the DNS switch a second after the core
  starts never flashes the warning. One canvas for all three
  states, so they scale together from the bar slot to the header. No ring:
  the owner picks a node by hand all the time, so a ring for manual mode was
  always on and read as noise (dropped 18.11.2026 at the owner's request).
- The bar shows the bolt alone. A country code as a text label beside it spilled
  into the neighbouring widget (the kit sizes an icon button to one slot); the
  country is in the tooltip and in the panel header's pill.

## Colour

- Every colour comes from the theme (`Color.*`, `SystemTheme`). No hex, no
  named colours; `tests/test_panel_source.sh` enforces it.
- `Color.accent`: download and upload (the arrows' direction tells them
  apart), connected, through the tunnel, the current choice. `Color.urgent`:
  failure, blocked, a protection that is off — trouble only; in a normal state
  there is no red on the card, as in Tailscale's. Theme green/yellow:
  fast/slow node delay.
- Colour alone never carries state. Delays are printed in milliseconds or
  words; the active subscription and the selected node have a filled dot or
  ring *and* the selected fill; a route is written out (tunnel / direct /
  blocked).

## Labels

- `…` (one character, never three dots) when activating opens something
  instead of completing the action: "Subscriptions…" opens a page, "Make
  active…" and "Update core…" open a confirmation. The test refuses `...`
  in the catalogs.
- Strings go through the shell's `Commons.Translations` and nothing else: the
  panel speaks the language picked under Setup > Language, English when none
  is. `i18n/en.json` and `i18n/ru.json` carry the same keys; no QML or JS file
  holds a Cyrillic letter (the test checks).
- Numbers go through `Commons.I18n.formatNumber`, dates through
  `Qt.locale(Commons.I18n.formatLocale)`. Units (B, KB, MB, KB/s, ms) stay as
  they are in every language.
- The CLI's sentences are for a terminal. The panel never shows them: it
  reads codes (`protection.codes`, `skipped[].code`, the `{ok, code,
  detail}` line of every verb it runs with `--json`) and says them in the
  catalog's words. A code the catalog does not know reads as a whole phrase
  ("unknown problem", "some links were skipped", "The tunnel did not
  start."), never as the code itself.
  Only text that is not the CLI's own goes on screen as is: xray's log lines,
  an exception's message, a journal line in `detail` — and even those are
  dropped if they contain Cyrillic.

## The panel's shape

The shell's Tailscale panel is the reference: one main screen, no tabs. The
first build had four tabs, six titled sections and a five-row protection
table; the owner rejected it as bulky, out of tune with the system and slow to
open. Every fresh open returns to the main screen with the search cleared,
the fold closed and the node order taken afresh.

- **Header** (`XrayHero`, PanelHero's twin): the state icon; the node
  carrying traffic as the title (or "VPN" when off); a caps line
  "DE · 203.0.113.7 · 465 ms" while connected, otherwise the state (OFF,
  STARTING, NOT PROTECTED, FAILURE); the on/off switch and the "more" menu on
  the right. The switch reads on while the core runs or systemd is starting
  it again (`service == activating`), so a tunnel that keeps retrying can
  always be turned off from here.
  PanelHero upper-cases its whole second line and "465 MS" reads as something
  else, so the twin keeps the delay out of the caps — the only difference.
  While a node switch runs the title names the node being switched to and the
  line says SWITCHING…; after it, CHECKING… until the next answer lands. The
  previous node's country and address are never shown under the new name.
- **One line of speed and today's traffic**, tunnel and direct summed: ↓ and
  ↑ now on the left, today's ↓ ↑ on the right in the dim caption size.
- **One line of protection**: a shield and "Protected" in the dim colour.
  When the CLI says `protection.ok == false` it is "Not protected" in
  `urgent`, with one line per problem code under it. The core's last three
  errors (the CLI already drops start-up noise) appear under it only when
  there are any, one line each, elided, the whole line in a tooltip.
- **Nodes**, as Tailscale lists exit nodes: "Auto" pinned on top with who the
  balancer is using now, then the nodes that answer, fastest first (never
  probed after them), and the dead ones folded into one "Unreachable: N" row
  that opens in place. The picked node has a check, the selected fill and
  bold. A search field appears past ten nodes. The list is a ListView that
  builds only the rows in view and stops growing at seven rows, so a 562-node
  subscription does not stretch the card. On open it is scrolled so the picked
  node sits mid-view (a dead pick opens the fold); a scroll bar stays visible
  while there is more to scroll, here and on the sites page.
- **The order is frozen while the panel is open.** It is taken when the panel
  opens and when the search text changes; polls only change the delays in the
  rows, drop vanished nodes and append new ones. The keyboard cursor holds a
  node id, never a row number. (The first build re-sorted every ten seconds
  and a row could slide under the cursor between looking and pressing Enter.)
- **The menu** ("⋮", drawn): "Subscriptions…", "Sites…", "Settings…",
  "Core…", "Update subscriptions".
  The first four open a second page in the same card with a back arrow; Esc
  or ← goes back. Second pages are Loaders, built only while shown.
- **On fallback.** One line under protection, only while `fallback.active`
  is true: the two-arrow glyph and "On fallback: Helsinki 1" in the theme's
  yellow — a notice, not an alarm: the tunnel works and comes back by itself.
  The bar's tooltip says "on the fallback node" too. Absent otherwise, so the
  main screen keeps its height (312 px with two nodes).
- **Subscriptions**: active marked (dot, fill, the word ACTIVE), node count,
  age of the last fetch, quota (`total=0` no cap, `expire=0` no end date),
  skipped links, and why the last update of that subscription failed. Facts
  are whole phrases packed into lines (`Model.packLines`): a narrow card
  wraps between phrases, never inside one, and a "·" only ever stands between
  two phrases on one line (a Flow left it hanging at line ends). The expiry
  date and the days left are one phrase. A name that does not fit beside the
  button is elided with the whole of it in a tooltip. "Make active..." asks
  first: it restarts the core and the tunnel drops for 1–2 s. The dialog opens
  on Cancel, so a double Enter does nothing.
- **Sites**: one row per host (the CLI folds repeats and counts them): host,
  number of connections, tunnel / direct / blocked in words, "by rule" when a
  rule covers the host now (the connection itself may have gone the other
  way before the rule was added), the node, time. A "⋮" on the hovered row, or a right click
  anywhere on it, opens "Always direct", "Always via tunnel", "Remove rule"
  (the one in force has a check; "Remove rule" only for a host that has a
  rule of its own). One menu per page, placed inside the card: the rows are a
  ListView that gets a new array every poll. Above the hosts, only when there
  are any, the rules: host, "always direct" / "always via tunnel", and a ×
  that removes it.
- **Settings**: "Notifications" with a switch; "Russia: send Russian sites
  direct" with a switch, off by default (everything goes through the tunnel
  until it is turned on; shown only when the CLI reports `presets`) — with the
  tunnel running it asks "Restart the core…?" first and runs the preset with
  `--apply`, with the tunnel off it only saves; then "Fallback node" with a
  switch, off by default. Under it the nodes it may fall back to: plain nodes
  of the active subscription that answer, not the selected one, fastest first
  (a ListView, five rows in view). The switch turns on only with a node
  picked by hand (not Auto) and a fallback node chosen; otherwise a line says
  which is missing. A fallback change that answers `restart_needed` asks
  "Restart the core…?" (opens on Cancel) and repeats the verb with
  `--apply`; Cancel leaves it saved with a "Restart core…" line on the page.
- **Core**: installed version, the newest version this package pins (what
  can be installed) and its date, the version kept for rollback, "An update
  is available." / "Up to date.", how the last update ended, and one line when
  XTLS has a newer release than the package pins ("comes with the next
  package update"). "Update core…" asks first (the connection drops for a few
  seconds; a failing new core is rolled back by itself); then "Updating…"
  until `core status` says the swap is done, and a notice by its code.
- One notice line under the header for the last action's outcome or a CLI
  that did not answer; three lines at most. Good news clears itself after
  12 s, a failure stays until dismissed.

## First run

- The backend is the `xray-omarchy` package (CLI `/usr/bin/xray-omarchy`, root
  helper `/usr/lib/xray-omarchy/xray-omarchy-helper`) plus the xray core in
  `/var/lib/xray-omarchy/core`, put there by the helper only when its SHA-256
  is one the package pins. The panel checks the first two with `test -x` (running a
  missing program would tell nothing) and the rest from `status.setup`.
- Missing anything: the main screen is one card — what is missing in words,
  and **Install required components…**, which closes the panel and opens
  Omarchy's floating terminal on `backend/install.sh` of the plugin's own
  folder. The script says what it installs, asks, builds the package in a
  temporary copy (never inside the plugin folder: every write there reloads
  the shell) and takes the password only for sudo, in that terminal. The
  panel never asks for a password and never runs sudo.
- Installed, no subscription: one card, **Add subscription…**, which opens
  the form page (link, optional name — the link's host when empty). Enter
  adds, Esc goes back. The Subscriptions page has the same button.
- Neither card shows the switch, protection or nodes: there is nothing to
  switch yet.
- Installed, but the package is older than the panel (`status.setup.version`
  below the `version` of the panel's own `manifest.json`, read as a file): one
  line on the main screen, "The installed components (0.5.0) are older than
  the panel (0.6.0)", and **Update components…**, which opens the same
  installer. A CLI that does not report its version gets no line.
- Pacman's databases older than what the installer needs (a fresh Omarchy
  before its first `omarchy update`: the offline database has no
  `v2ray-geoip`): the install button runs `backend/install.sh --check` first
  (no sudo, no changes; `pacman -Sp` on what is missing). Exit 3: the notice
  line says "Your package databases are out of date. Run `omarchy update` first, then press Install again.", the panel stays open
  and no terminal opens. The installer itself never runs `pacman -Sy` (a
  partial upgrade). Any other result of the check opens the installer as
  before; the panel closes once the terminal is launched.
- The plugin updated under a running shell (`omarchy plugin update`): the
  shell keeps the code it loaded. `Model.PANEL_VERSION` (the running code)
  older than the `version` of `manifest.json` on disk (watched, and read again
  on each open): one line on the main screen, "The panel was updated to
  0.6.4. Restart the shell to finish updating.", and **Restart the shell**
  (`omarchy restart shell`, detached). It goes before "Update components…",
  which waits until the new code runs.
- The package removed while the shell runs (`pacman -R`, `uninstall.sh`): the
  next poll cannot start the CLI, the panel checks again with `test -x` and
  drops its last answer — back to the first-run card, never a stale
  "Protected".

## Opening fast

Measured, not guessed (screen recording at 60 fps, frames from the first
visible frame of the card to the last change; see the builder's report for
the numbers). What keeps it fast:

- The content is built once, on the first open (`KeyboardPanel.content`), and
  kept — the shell's own panels do the same.
- The service polls with the panel closed too, with the node table, so the
  card opens on cached data at its final height. Nothing on open changes the
  layout; the fresh poll comes 400 ms later, after the 180 ms open animation,
  and only changes numbers in place.
- The card is small: one screen of about 300 px instead of 750.

## What the panel may run

- `xray-omarchy status --json --nodes` every 3 s open / 15 s closed, plus once 400 ms
  after an open and once right after a node switch. A poll never starts over
  one still running; one that was already out when a switch ended is dropped
  and asked again. A 20 s watchdog reaps polls only. `--nodes` costs the CLI
  nothing extra (0.13 s either way). `--refresh` (its own process, up to 8 s)
  only when the node carrying traffic changes without the panel asking — the
  balancer in Auto; `xray-omarchy select` re-checks the exit itself.
- `xray-omarchy on --json` / `xray-omarchy off --json` from the header switch only. The last
  line is `{ok, code, detail}`; a failure shows the sentence for its code and
  the core's journal line, and lets the knob go. The lines before it are the
  CLI's text for a terminal and are ignored; without the JSON line only
  the exit code is shown. The knob follows the requested position until the
  CLI confirms it, 60 s at most.
- `xray-omarchy select --json <id|auto>` from a node row, Enter on the node list, or
  IPC `select`. Latest pick wins; the id must match `^[0-9a-f]{10}$`. A
  refusal (`not_found`) is a sentence; `restarted` and `restart_needed` are
  calm notices.
- `xray-omarchy use --json -- <name>` only after the confirmation, detached (the
  restart outlives the panel); the name must be one the CLI reported and goes
  after `--`. Detached, so its result line is not read: its two refusals
  (unknown name, no nodes) cannot happen from the button, and the 45 s
  deadline catches anything else.
- `xray-omarchy fallback set <id> | on | off --json` from the settings page;
  `--apply` only after the restart confirmation.
- `xray-omarchy notify on|off --json` from the settings switch.
- `xray-omarchy preset russia on|off --json` from the settings switch, with
  `--apply` only after the restart confirmation. The name must be one
  `Model.validPreset` knows.
- `xray-omarchy rule add direct|tunnel --json -- <host>` and `xray-omarchy rule rm --json --
  <host>` from the sites page. The host must be one the CLI reported
  (`recent[]` or `rules`) and match the CLI's own host rule (lowercase
  domain with a dot or IPv4, `Model.ruleHost`); a clipped or odd host gets no
  actions.
- `xray-omarchy core status --json` while the core page is shown (once on open) and
  every 2 s while an update runs; never in the regular poll. `xray-omarchy core
  update --json` only after the confirmation; `started` hands over to the
  detached unit and the panel follows `update.state` to `done` (or `lost`).
  Never `--force` or `--dry-run`.
- `xray-omarchy update --json` from the menu or `u`: one result per subscription; any
  failure (the CLI exits non-zero) is a failure notice naming the
  subscriptions and their reasons (exception text, English). Never `--apply`.
- `test -x <cli> -a -x <helper>` until both are there, instead of the status poll.
- `<plugin>/backend/install.sh --check` from the install and "Update
  components…" buttons, before the terminal (argv, no shell, no sudo).
- `omarchy-launch-floating-terminal-with-presentation '<plugin>/backend/install.sh'`
  from the install and "Update components…" buttons only, after the check
  (the path single-quoted for the launcher's command line), detached.
- `omarchy restart shell` from the "Restart the shell" button only, shown only
  while the manifest on disk is newer than the running code; detached (it
  stops this shell).
- `xray-omarchy sub add --json -- <name> <url>` then `xray-omarchy update --json
  --name=<name>` from the form only; the link must pass `Model.subscriptionUrl`
  (one http(s) link, no spaces or control characters) and the name
  `Model.subscriptionName` (1–40 characters, not starting with `-`). A plain
  `http://` link (`Model.insecureUrl`) shows a warning and is sent, with
  `--allow-http` before `--`, only after the form's separate "Allow plain HTTP"
  button for that very link; without it the CLI refuses it (`insecure_url`).
- Never through a shell (the launcher above is the one command line, and it
  carries only the quoted path). No key, no IPC verb and no bar click turns the tunnel
  off, switches the subscription, changes the fallback, the notifications,
  a preset or a rule, or updates the core. IPC `showPage` only shows pages (and the menu).

## Text

Node names, hosts, subscription titles and log lines are someone else's
strings. Every `Text` is PlainText, everything is clipped in `Model.js`
before it reaches QML, and lists are bounded there as well as in the CLI.
