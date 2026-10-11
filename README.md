# Kobo domotics dashboard

Turn a Kobo Clara e-reader into an always-on e-ink dashboard for Home Assistant.

[Puppet](https://github.com/balloob/home-assistant-addons), a headless Chrome add-on, takes a PNG screenshot of a Home Assistant dashboard view. `dash.sh` runs on the Kobo, downloads that PNG on a timer and draws it straight to the e-ink framebuffer with [FBInk](https://github.com/NiLuJe/FBInk).

Background and build log: [E-ink domotics dashboard using Home Assistant, Puppet and FBInk on Kobo Clara](https://hashbang.nl/blog/eink-domotics-dashboard-using-homeassistant-puppet-and-fbink-on-kobo-clara)

## How it works

```
Home Assistant dashboard ──► Puppet (headless Chrome) ──► PNG over HTTP
                                                              │
                                     Kobo: dash.sh ── wget ───┘
                                                │
                                                └── fbink ──► e-ink screen
```

When `dash.sh` starts, it:

- stops the Kobo UI (`nickel`) and its watchdog (`hindenburg`) so it has the screen to itself
- starts `dropbear` so you can still SSH in after the UI is gone
- downloads the screenshot to a temp file and only replaces the last good image if the download succeeds
- redraws the screen without a flash, and does a full flashing refresh every 10th draw to clear ghosting
- refreshes every 30 s from 06:00 to 10:00 and every 120 s the rest of the day
- logs every draw with the battery level and charge status to `/mnt/onboard/.dash/dash.log`, flushes each line to disk so the log survives a hard power cut, and trims the log to 2000 lines

## Requirements

**Kobo:**
- Kobo Clara or a similar Kobo; the defaults assume a 1448x1072 screen in landscape
- [KFMon](https://github.com/NiLuJe/kfmon) to start the script from the home screen. It comes with the [one-click KOReader install packages](https://www.mobileread.com/forums/showthread.php?t=314220)
- SSH access. Enable the SSH server in KOReader for a root shell
- FBInk. Use a recent build from the [FBInk GitHub Actions](https://github.com/NiLuJe/FBInk/actions): the v1.25.0 release from 2022 doesn't support newer Kobo models

**Server:**
- Home Assistant
- The Puppet add-on (or its container under docker-compose), reachable from the Kobo's network

## Setup

### 1. Home Assistant dashboard

Make a dashboard view sized for the Kobo, for example at `/kobo-dashboard/0`. Some things that help on e-ink:

- Markdown cards are an easy way to show values in a larger font
- History bar charts and line graphs render well
- Emoji give quick visual cues without colour
- Keep to the default card styling

Open the view through Puppet to check it:

```
http://<puppet-host>:10000/kobo-dashboard/0?viewport=1448x1072&zoom=1.76&rotate=90
```

### 2. Configure

```sh
cp dash.env.example dash.env
```

Set `BASE_URL` in `dash.env` to your Puppet host and dashboard path. `dash.env` is gitignored, so your network details stay out of the repo.

The rest of the settings are at the top of `dash.sh`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `QUERY` | viewport, colours, rotate, zoom | Puppet screenshot parameters |
| `FBINK` | `fbink` | Path to the FBInk binary; use the full path if KFMon can't find it on `PATH` |
| `LOG_DIR` | `/mnt/onboard/.dash` | Folder for the log |
| `INTERVAL_NORMAL` | `120` | Seconds between refreshes |
| `INTERVAL_MORNING` | `30` | Seconds between refreshes from `MORNING_START` to `MORNING_END` |
| `MORNING_START` / `MORNING_END` | `6` / `10` | Faster refresh window (hours, end not included) |
| `DEGHOST_EVERY` | `10` | Full flashing refresh every Nth draw |
| `MAX_LOG_LINES` | `2000` | Log is trimmed to this many lines |

Puppet query parameters: `viewport` (screenshot size), `colors` (greyscale palette for the e-ink panel), `lang`, `rotate` (90 for landscape), `zoom`, and optionally `wait` (milliseconds to wait before taking the screenshot).

You can point the script at a different env file with `DASH_ENV=/path/to/dash.env`.

### 3. Install on the Kobo

Copy `dash.sh` and `dash.env` to the same folder on the Kobo. Copy the FBInk binary too, and make sure the script can run it:

```sh
scp dash.sh dash.env root@<kobo-ip>:/mnt/onboard/.adds/dash/
ssh root@<kobo-ip> chmod +x /mnt/onboard/.adds/dash/dash.sh
```

Then add a KFMon launcher for `dash.sh`, so tapping its cover image on the Kobo home screen starts the dashboard.

## Troubleshooting

- **Read the log:** `tail -f /mnt/onboard/.dash/dash.log`. Each line has a timestamp and the battery level and status, which helps tell a network problem from a flat battery.
- **`FETCH FAILED`:** The Kobo can't reach Puppet, or Puppet returned nothing. The last good image stays on screen. After 3 failures in a row it is redrawn with a flash, so you can see the screen is out of date.
- **`missing .../dash.env`:** `dash.env` isn't in the same folder as `dash.sh`.
- **Getting the normal Kobo UI back:** Restart the device, or run `reboot` over SSH.

## Files

| File | Purpose |
| --- | --- |
| `dash.sh` | The dashboard loop that runs on the Kobo |
| `dash.env.example` | Template for `dash.env` (local, gitignored) |
