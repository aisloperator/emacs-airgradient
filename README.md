# airgradient.el

An Emacs package for fetching and displaying air quality data from an
[AirGradient](https://www.airgradient.com/) sensor, using the
[AirGradient public API](https://api.airgradient.com/public/docs/api/v1/).

## Installation

Put `airgradient.el` on your `load-path` and:

```elisp
(require 'airgradient)
```

## Configuration

- `airgradient-token` — API access token for your AirGradient place.
  Defaults to a demo token. Get your own token from the Place settings
  page at <https://app.airgradient.com/settings/place> and set it via
  `M-x customize-variable RET airgradient-token RET` or in your init
  file:

  ```elisp
  (setq airgradient-token "your-token-here")
  ```

- `airgradient-location-id` — optional numeric id of a single location
  to use by default. When `nil` (the default), all locations for the
  place identified by `airgradient-token` are fetched.

- `airgradient-fahrenheit-p` — if non-nil, report temperature in
  Fahrenheit instead of Celsius. This also changes the output label
  from `temperature-c` to `temperature-f`.

## Usage

Run `M-x airgradient-insert` to insert a rendering of the current
measures at point. With a prefix argument (`C-u M-x airgradient-insert`),
you're prompted for a specific numeric location id instead of using the
default.

Each location is rendered as one dense ASCII line, for example:

```
AirGradient Home 199161 2026-07-17T01:08:51Z location indoor model I-9PSL-DE serial d83bda1ab538 firmware 3.6.2 pm1-ug/m3 1.5 pm2.5-ug/m3 4.8 (corrected 2.9) pm10-ug/m3 4.8 pm0.3-particles/dl 255 co2-ppm 622 temperature-c 26.9 humidity-% 44 tvoc-ppb 208.3 tvoc-index 204 nox-index 1 wifi-signal -26
```

Fields with no data for a given sensor (e.g. `battery-v`, `gps`) are
omitted from the line.

You can also call the fetch function directly from Lisp:

```elisp
(airgradient-fetch-current-measures)              ; all locations for the place
(airgradient-fetch-current-measures 199161)       ; one specific location
```

which returns the parsed JSON (a list of alists, or a single alist when
a location id is given).

## License

No license specified.
