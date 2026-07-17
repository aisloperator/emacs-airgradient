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
   space-separated ASCII line* (not a multi-line block), via
   `airgradient--format-measure` and small helpers
   (`airgradient--kv`, `airgradient--fmt-corrected`,
   `airgradient--fmt-timestamp`). This exact format was specified
   directly by the user, e.g.:
   `AirGradient Home 199161 2026-07-17T01:08:51Z location indoor model I-9PSL-DE serial d83bda1ab538 firmware 3.6.2 pm1-ug/m3 1.5 pm2.5-ug/m3 4.8 (corrected 2.9) pm10-ug/m3 4.8 ... wifi-signal -26`.
   Fields are built as a list of `(label value)` or plain tokens,
   `nil`-filtered with `delq`, then `mapconcat`ed with `" "` — a
   missing field (e.g. no `battery-v` on a given sensor model) simply
   drops out of the line rather than leaving a blank. Corrected sensor
   values (e.g. `pm02_corrected`) are only shown in parens when they
   differ from the raw value. Timestamps have fractional seconds
   stripped (`2026-07-17T01:08:51.000Z` -> `2026-07-17T01:08:51Z`) by
   `airgradient--fmt-timestamp`, which needed a capture-group rewrite
   instead of a lookahead since Emacs regexps don't support lookahead.
   The temperature field is computed (via `airgradient--celsius-to-fahrenheit`,
   which rounds to 1 fraction digit) and relabeled *before* the
   `delq`/`mapconcat` pipeline, so the raw-vs-corrected "differs"
   comparison in `airgradient--fmt-corrected` runs on whichever unit
   is active rather than always on Celsius.
5. **Command** — `airgradient-insert` is the only interactive
   entry point; with a prefix arg it prompts for a numeric location id,
   otherwise falls back to `airgradient-location-id`, otherwise fetches
   every location for the token's place.

The full field list (units, corrected variants, etc.) comes from the
API's OpenAPI/Swagger spec, fetched at
`https://api.airgradient.com/public/docs/api/v1/swagger.json` (the
Swagger UI HTML page itself is just a JS shell and returns no useful
content to a plain fetch — get the spec JSON directly instead).
