;;; airgradient.el --- Fetch and display AirGradient air quality data -*- lexical-binding: t; -*-

;; Keywords: comm, hardware
;; Package-Requires: ((emacs "27.1"))

;; Created by AI Sloperator (https://www.aisloperator.com/) using
;; Claude Code, on 2026-07-16.

;;; Commentary:

;; Fetches current air quality measures from the AirGradient sensor
;; API (https://api.airgradient.com/public/docs/api/v1/) and can
;; insert a human-readable ASCII rendering of that data into a
;; buffer.
;;
;; Configure `airgradient-token' with your place's API token (see
;; https://app.airgradient.com/settings/place).  A demo token is
;; used by default.
;;
;; Usage:
;;
;;   M-x airgradient-insert
;;
;; inserts a rendering of the current measures for every location
;; associated with the configured token at point.  With a prefix
;; argument, you are prompted for a specific numeric location id.

;;; Code:

(require 'url)
(require 'url-http)
(require 'json)
(require 'let-alist)

(defvar url-http-end-of-headers)

(defgroup airgradient nil
  "Fetch and display AirGradient air quality sensor data."
  :group 'comm
  :prefix "airgradient-")

(defcustom airgradient-token "58b83963-4194-495f-88ca-beab7739c467"
  "API access token for an AirGradient place.
Obtain your own token from the Place settings page at
https://app.airgradient.com/settings/place"
  :type 'string
  :group 'airgradient)

(defcustom airgradient-location-id nil
  "Default location id to use when none is given interactively.
When nil, `airgradient-insert' and `airgradient-fetch-current-measures'
fetch the current measures for every location of the place identified
by `airgradient-token'."
  :type '(choice (const :tag "All locations of the place" nil)
                  (integer :tag "Specific location id"))
  :group 'airgradient)

(defconst airgradient--api-base-url "https://api.airgradient.com/public/api/v1"
  "Base URL of the AirGradient public API.")

(defun airgradient--request (path &optional token)
  "Perform a GET request to PATH on the AirGradient API and return parsed JSON.
PATH is relative to `airgradient--api-base-url', e.g.
\"/locations/measures/current\".  TOKEN defaults to `airgradient-token'.
Signals a `user-error' if the HTTP response is not successful."
  (let* ((url-request-method "GET")
         (url (format "%s%s?token=%s"
                      airgradient--api-base-url
                      path
                      (url-hexify-string (or token airgradient-token))))
         (buffer (url-retrieve-synchronously url t t 15)))
    (unless buffer
      (user-error "AirGradient API request timed out or failed: %s" path))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (let ((status (url-http-parse-response)))
            (unless (and (>= status 200) (< status 300))
              (user-error "AirGradient API request to %s failed with HTTP status %d"
                          path status))
            (goto-char url-http-end-of-headers)
            (json-parse-buffer :object-type 'alist :array-type 'list
                                :null-object nil :false-object nil)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun airgradient-fetch-current-measures (&optional location-id token)
  "Fetch current AirGradient measures and return them as parsed JSON.
If LOCATION-ID is non-nil, fetch just that location's current measures,
returning a single alist.  Otherwise fetch the current measures of every
location for the place identified by TOKEN (or `airgradient-token'),
returning a list of alists, one per location."
  (if location-id
      (airgradient--request (format "/locations/%d/measures/current" location-id) token)
    (airgradient--request "/locations/measures/current" token)))

(defun airgradient--measure-list-p (data)
  "Return non-nil if parsed JSON DATA is a list of measures rather than one."
  (and (consp data) (consp (car data)) (consp (caar data))))

(defun airgradient--fmt (value)
  "Format VALUE as a string, or return nil if VALUE is nil."
  (when value (format "%s" value)))

(defun airgradient--fmt-corrected (raw corrected)
  "Format RAW value, appending CORRECTED in parens if it differs from RAW."
  (when raw
    (if (and corrected (not (equal corrected raw)))
        (format "%s (corrected %s)" raw corrected)
      (format "%s" raw))))

(defun airgradient--kv (label value)
  "Format \"LABEL VALUE\", or nil if VALUE is nil."
  (when value (format "%s %s" label value)))

(defun airgradient--fmt-timestamp (timestamp)
  "Format TIMESTAMP, stripping any fractional seconds, e.g. \".000\"."
  (when timestamp
    (replace-regexp-in-string
     "\\.[0-9]+\\(Z\\|[+-][0-9:]+\\)?\\'" "\\1" timestamp)))

(defun airgradient--format-measure (measure)
  "Render a single MEASURE alist as one dense line of human-readable ASCII."
  (let-alist measure
    (mapconcat
     #'identity
     (delq nil
           (list "AirGradient"
                 .locationName
                 (airgradient--fmt .locationId)
                 (airgradient--fmt-timestamp .timestamp)
                 (airgradient--kv "location" .locationType)
                 (airgradient--kv "model" .model)
                 (airgradient--kv "serial" .serialno)
                 (airgradient--kv "firmware" .firmwareVersion)
                 (airgradient--kv "pm1-ug/m3" (airgradient--fmt-corrected .pm01 .pm01_corrected))
                 (airgradient--kv "pm2.5-ug/m3" (airgradient--fmt-corrected .pm02 .pm02_corrected))
                 (airgradient--kv "pm10-ug/m3" (airgradient--fmt-corrected .pm10 .pm10_corrected))
                 (airgradient--kv "pm0.3-particles/dl" (airgradient--fmt .pm003Count))
                 (airgradient--kv "co2-ppm" (airgradient--fmt-corrected .rco2 .rco2_corrected))
                 (airgradient--kv "temperature-c" (airgradient--fmt-corrected .atmp .atmp_corrected))
                 (airgradient--kv "humidity-%" (airgradient--fmt-corrected .rhum .rhum_corrected))
                 (airgradient--kv "tvoc-ppb" (airgradient--fmt .tvoc))
                 (airgradient--kv "tvoc-index" (airgradient--fmt .tvocIndex))
                 (airgradient--kv "nox-index" (airgradient--fmt .noxIndex))
                 (airgradient--kv "wifi-signal" (airgradient--fmt .wifi))
                 (airgradient--kv "battery-v" (airgradient--fmt .batteryVoltage))
                 (airgradient--kv "panel-v" (airgradient--fmt .panelVoltage))
                 (and .latitude .longitude (airgradient--kv "gps" (format "%s,%s" .latitude .longitude)))
                 (and .anomalies (airgradient--kv "anomalies" (mapconcat #'identity .anomalies ",")))))
     " ")))

(defun airgradient--format-measures (data)
  "Render parsed JSON DATA (one measure or a list of measures) as ASCII text.
Each measure is rendered as one dense line, terminated with a newline."
  (if (airgradient--measure-list-p data)
      (if data
          (concat (mapconcat #'airgradient--format-measure data "\n") "\n")
        "No AirGradient locations found.\n")
    (concat (airgradient--format-measure data) "\n")))

;;;###autoload
(defun airgradient-insert (&optional location-id)
  "Insert a human-readable rendering of current AirGradient measures at point.
With a prefix argument, prompt for a specific numeric LOCATION-ID.
Otherwise use `airgradient-location-id' if set, or else show every
location for the place identified by `airgradient-token'."
  (interactive
   (list (when current-prefix-arg
           (read-number "AirGradient location id: "))))
  (let* ((location-id (or location-id airgradient-location-id))
         (data (airgradient-fetch-current-measures location-id)))
    (insert (airgradient--format-measures data))))

(provide 'airgradient)

;;; airgradient.el ends here
