# Hustle HQ

Single-page DoorDash offer analyzer. Runs entirely in your browser; your log and settings stay in that browser's storage.

- `index.html` is the whole app (plus PWA files: `manifest.webmanifest`, `sw.js`, icons).
- Open the Pages link, then Share > Add to Home Screen on iPhone.
- Log format: `date,time,zone,payout,miles,items,minutes,verdict,choice`

**Never commit** your DoorDash `data_archive.zip`, statement PDFs, `offers.txt` or `settings.json`. `.gitignore` blocks them.
