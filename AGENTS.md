# Working agreements

- `DESIGN.md` is the standard for the surface: icons, colour, labels, the
  panel's shape, and what the panel may run. Read it before touching a
  component and change it together with the behaviour it describes.
- The only backend is the `xray-omarchy` CLI (`/usr/bin/xray-omarchy`, from the `xray-omarchy` package built from `backend/`). The panel reads
  `xray-omarchy status --json` and runs a fixed set of its verbs as argv arrays.
- Colours come from `qs.Commons.Color` and the theme (`SystemTheme`). No hex,
  no named display colours.
- Every `Text` is `textFormat: Text.PlainText`.
- Strings go through `Commons.Translations` and `i18n/{en,ru}.json`; both
  catalogs carry the same keys. No Cyrillic outside `i18n/ru.json` (except
  the test strings that feed Model.js's Cyrillic filter); the CLI's terminal
  text never reaches the screen — the panel reads its codes.
- Work on a copy outside `~/.config/omarchy/plugins/`: every save in that
  directory reloads the whole shell. Copy the finished version in once.
- Run `make validate` after QML or behaviour changes.
