# Hustle HQ

Single-page DoorDash offer analyzer. Runs entirely in your browser; your log and settings stay in that browser's storage.

- `index.html` is the whole app (plus PWA files: `manifest.webmanifest`, `sw.js`, icons).
- Open the Pages link, then Share > Add to Home Screen on iPhone.
- Log format: `date,time,zone,payout,miles,items,minutes,verdict,choice`

**Never commit** your DoorDash `data_archive.zip`, statement PDFs, `offers.txt` or `settings.json`. `.gitignore` blocks them.

## Starting from an established account

Most dashers already have history, so the Scoreboard opens on a **Start here** card:

1. Add `data_archive.zip` (History tab) for every delivery's date, time, store and items.
2. Add the monthly statement PDFs (Earn tab). Each month's total is then exact, to the cent.
3. Enter your Accepted and Declined counts from DoorDash > Ratings > Acceptance rate.

Per-delivery pay and miles are estimates that add up to each statement total. Months with no statement yet stay estimated and are listed as such. The **Decline float** card shows how many declines are left before your rolling-100 rate drops under the Float target in Settings, and flags NO FLOAT.
