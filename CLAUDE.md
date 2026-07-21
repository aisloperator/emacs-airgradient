# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`airgradient.el` is a single-file Emacs Lisp package (no build system,
no test suite) that fetches air quality data from the AirGradient
public API (https://api.airgradient.com/public/docs/api/v1/) and
provides `M-x airgradient-insert` to insert a human-readable rendering
at point. See README.md for user-facing usage and configuration.

## Commands

There is no Makefile, Eask file, or test suite. Use these directly:

```sh
# Byte-compile and surface warnings (delete the .elc afterward; it's a build byproduct, not checked in)
emacs -Q --batch -L . -f batch-byte-compile airgradient.el
rm -f airgradient.elc

# checkdoc lint
emacs -Q --batch -L . --eval "(with-current-buffer (find-file-noselect \"airgradient.el\") (checkdoc-current-buffer t))"

# Manual smoke test against the live API (uses the default demo token)
emacs -Q --batch -L . --eval "
(progn
  (require 'airgradient)
  (with-temp-buffer
    (airgradient-insert)
    (princ (buffer-string))))
"
```

There are no unit tests. Verifying a change means byte-compiling clean
and running the manual smoke test above against the real API to
confirm the output line still looks right.

## Architecture

The file is organized as a small pipeline, top to bottom:

1. **Config** — `airgradient-token` (defcustom, defaults to a public
   demo token), `airgradient-location-id` (optional default
   location; `nil` means "all locations for the place"), and
   `airgradient-fahrenheit-p` (if non-nil, convert `atmp`/`atmp_corrected`
   to Fahrenheit and relabel the field `temperature-f` instead of
   `temperature-c`).
2. **Transport** — `airgradient--request` does a synchronous GET via
   `url-retrieve-synchronously`, checks the HTTP status via
   `url-http-parse-response`, and parses the body with
   `json-parse-buffer` starting at `url-http-end-of-headers` (a
   dynamically-bound var from `url-http.el`; it's declared with a bare
   `(defvar url-http-end-of-headers)` forward declaration near the top
   of the file purely to silence the byte-compiler, since `require`
   alone doesn't expose it as a known special variable at compile
   time).
3. **API** — `airgradient-fetch-current-measures` picks between the
   "all locations" endpoint (`/locations/measures/current`, returns a
   JSON array) and the "single location" endpoint
   (`/locations/{id}/measures/current`, returns a single JSON object).
   `airgradient--measure-list-p` distinguishes the two parsed shapes: a
   single measure is an alist of `(symbol . value)` pairs, so
   `(caar data)` is a symbol; a list of measures has alists as its
   elements, so `(caar data)` is itself a cons.
4. **Rendering** — each measure is rendered as *one dense
   space-separated ASCII line* (not a multi-line block). There are two
   renderers sharing the same small helpers (`airgradient--kv`,
   `airgradient--fmt-corrected`, `airgradient--fmt-unit`,
   `airgradient--fmt-timestamp`):
   - `airgradient--format-measure` is the original, detailed renderer,
     e.g.:
     `AirGradient Home 199161 2026-07-17T01:08:51Z location indoor model I-9PSL-DE serial d83bda1ab538 firmware 3.6.2 pm1-ug/m3 1.5 pm2.5-ug/m3 4.8 (corrected 2.9) pm10-ug/m3 4.8 ... wifi-signal -26`.
     Fields are built as a list of `(label value)` or plain tokens,
     `nil`-filtered with `delq`, then `mapconcat`ed with `" "` — a
     missing field (e.g. no `battery-v` on a given sensor model) simply
     drops out of the line rather than leaving a blank. Corrected
     sensor values (e.g. `pm02_corrected`) are only shown in parens
     when they differ from the raw value. Timestamps have fractional
     seconds stripped (`2026-07-17T01:08:51.000Z` ->
     `2026-07-17T01:08:51Z`) by `airgradient--fmt-timestamp`, which
     needed a capture-group rewrite instead of a lookahead since Emacs
     regexps don't support lookahead.
   - `airgradient--format-measure-brief` is the newer, terser default
     renderer, e.g.: `AirGradient Home 80.2F 56% pm2.5-ug/m3 7.3
     co2-ppm 486 tvoc-index 133 nox-index 1`. It drops location
     id/timestamp/model/serial/firmware/pm1/pm10/pm0.3/wifi/battery/
     panel/gps/anomalies, and for temperature, humidity, PM2.5, and
     CO2 it collapses the raw-vs-corrected pair down to a single value
     (corrected if present, via `(or corrected raw)`, otherwise raw)
     instead of showing both like the detailed renderer does.
     Temperature and humidity are also written unit-suffixed with no
     space (`80.2F`, `56%`) via `airgradient--fmt-unit`, rather than as
     a labeled `temperature-f`/`humidity-%` pair. `tvoc-ppb` (the raw
     ppb reading) is omitted in favor of `tvoc-index` alone, since
     that's what AirGradient's own dashboard UI favors.
   - In both renderers the temperature field is computed (via
     `airgradient--celsius-to-fahrenheit`, which rounds to 1 fraction
     digit) *before* the corrected-vs-raw comparison, so that
     comparison runs on whichever unit is active rather than always on
     Celsius.
   - `airgradient--format-measures` takes the renderer to use as a
     `formatter` argument, so both commands below share the same
     one-measure-vs-list-of-measures dispatch logic.
5. **Commands** — `airgradient-insert` is the sole
   `;;;###autoload`'d, interactive entry point, and uses
   `airgradient--format-measure-brief`; with a prefix arg it prompts
   for a numeric location id, otherwise falls back to
   `airgradient-location-id`, otherwise fetches every location for the
   token's place. `airgradient-insert-legacy` has the identical
   location-id-resolution logic but is a plain (non-interactive,
   non-autoloaded) function using `airgradient--format-measure`,
   kept only so the original, detailed rendering remains reachable
   from Lisp (e.g. `M-:`) without cluttering `M-x` completion.

The full field list (units, corrected variants, etc.) comes from the
API's OpenAPI/Swagger spec, fetched at
`https://api.airgradient.com/public/docs/api/v1/swagger.json` (the
Swagger UI HTML page itself is just a JS shell and returns no useful
content to a plain fetch — get the spec JSON directly instead).
