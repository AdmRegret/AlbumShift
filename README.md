# AlbumShift

Rotate your KDE Plasma wallpaper from a shared photo album: **Google Photos**, **iCloud**, or **Immich**.

It reads the full album, pulls a small random batch sized to your screen, and steps through it on a timer. When the batch runs out, it fetches a fresh random batch. Portrait photos can be skipped or placed over a blurred background so they don't stretch.

## Why I built this

After moving to Linux, I wanted my desktop wallpaper to rotate through a Google Photos album. I was unable to find a tool that fit what I was looking to do, so I worked with Claude to build a script for Google Photos, later extended to iCloud and Immich. AlbumShift reads a shared album link directly, so there's no API key, no OAuth, and no manual exporting. Pick an album, and your desktop keeps cycling through it.

## Supported sources

| Source | Link to use | Credentials | Status |
|---|---|---|---|
| Google Photos | Shared album link (`photos.app.goo.gl/...` or older `goo.gl/photos/...`) | None | Tested |
| iCloud | Shared album **Public Website** link, legacy (`www.icloud.com/sharedalbum/#...`) or new (`photos.icloud.com/shared/album/...`) | None | Untested, see below |
| Immich | Album page URL (`https://<server>/albums/<album-id>`) | API key | Tested against a mock server only |

The source is detected from `ALBUM_URL`.

### Why share links for Google Photos

Since March 31, 2025, the Google Photos Library API only exposes media an app created itself, so wallpaper tools can no longer read your existing library. A link-shared album is still publicly viewable, and this script reads it the same way the Photos web page does.

## Requirements

- KDE Plasma (uses `plasma-apply-wallpaperimage`, works on Wayland)
- `bash`, `python3` (standard library only), `shuf` (coreutils)
- ImageMagick (blur fill and image dimensions)

On Fedora:

```bash
sudo dnf install python3 ImageMagick
```

Other desktop environments should be easy to support. The wallpaper is set on a single line in `apply_next()`, and the `plasma-apply-wallpaperimage` dependency checks in `albumshift` and `install.sh` would need the same swap.

## Install

1. Get an album link:
   - **Google Photos.** Open the album, choose **Share → Create link**, and copy the link.
   - **iCloud.** In the Photos app, open the shared album, tap the people icon, turn on **Public Website**, and copy the link.
   - **Immich.** Open the album in the web UI and copy the URL from the address bar. Create an API key under **Account Settings → API Keys** with at least `asset.read` and `asset.view`.
2. Install:
   ```bash
   git clone https://github.com/AdmRegret/AlbumShift.git
   cd AlbumShift
   ./install.sh
   ```
3. Edit `~/.config/albumshift.conf`, set `ALBUM_URL` (and `IMMICH_API_KEY` for Immich) and your screen resolution, then:
   ```bash
   albumshift refresh
   ```
4. In Plasma, right-click the desktop → **Desktop and Wallpaper** and make sure the wallpaper type is **Image**, not Slideshow.

The installer copies the script to `~/.local/bin`, creates the config if missing, and enables a systemd user timer that rotates every 15 minutes.

## Usage

| Command | What it does |
|---|---|
| `albumshift` or `albumshift next` | Show the next photo (re-indexes if the index is older than `INDEX_TTL` or `ALBUM_URL` changed) |
| `albumshift refresh` | Re-index the album, download a new batch, show the first photo |
| `albumshift status` | Source, album count (landscape/portrait), batch remaining, current photo |

Next-photo hotkey: **System Settings → Keyboard → Shortcuts → Add New → Command or Script**, enter `albumshift next`.

Logs: `journalctl --user -u albumshift`

## Configuration

`~/.config/albumshift.conf`

| Setting | Default | Notes |
|---|---|---|
| `ALBUM_URL` | | Album link (required), see Supported sources |
| `IMMICH_API_KEY` | | Immich only |
| `BATCH` | `10` | Photos per download batch |
| `SCREEN_W` / `SCREEN_H` | `3840` / `2160` | Main monitor resolution (`kscreen-doctor -o`) |
| `PORTRAIT` | `blur` | `skip`, `blur`, or `keep` |
| `INDEX_TTL` | `21600` | Seconds between album re-index |

To change the rotation interval, edit `OnUnitActiveSec` in `~/.config/systemd/user/albumshift.timer`, then run `systemctl --user daemon-reload`.

## How it works

1. **Index.** An embedded Python helper (standard library only) lists the album's photos with their dimensions, skipping videos, and caches the list in `~/.cache/albumshift/index.tsv`.
   - **Google Photos.** Reads the album and auth keys from the share page, then pages through Google's `batchexecute` endpoint (`snAcKc` RPC, 300 items per page).
   - **iCloud, legacy links.** Calls the shared-streams `webstream` endpoint on the album's partition host, following Apple's `330` partition redirect if needed.
   - **iCloud, new links.** Resolves the short link through CloudKit's public `records/resolve`, then pages `records/query` with the anonymous access token.
   - **Immich.** Pages `POST /api/search/metadata` filtered to the album, with the `x-api-key` header.
2. **Batch.** Shuffles the index, takes `BATCH` photos, and downloads them. Google photos are requested at screen size, iCloud uses the largest JPEG derivative, and Immich uses the `fullsize` thumbnail (falling back to `preview`). Each file's real dimensions are read with ImageMagick, and portraits are skipped, blurred, or kept per `PORTRAIT`.
3. **Rotate.** Each run applies the next file from the queue with `plasma-apply-wallpaperimage`. The file currently on screen is kept while the next batch is fetched.

If an index refresh fails, the last good index keeps being used. If every download in a batch fails (for example, expired iCloud image links), the album is re-indexed once and the batch is retried.

## Caveats

- **Undocumented endpoints.** Google Photos and iCloud support rely on the same web endpoints their own sites use, which aren't public APIs. If either company changes them, indexing breaks until the parsing is updated. Rotation continues from the cached index in the meantime.
- **iCloud is untested.** The iCloud code follows a working open-source implementation (see Credits) and passes parser tests with mocked responses, but hasn't been run against a real album. Please open an issue with the `albumshift refresh` output if it fails.
- **Immich is tested against a mock server only.** It uses Immich's documented API, but older Immich versions may lack the `fullsize` thumbnail size (the script falls back to `preview`, which is lower resolution) or the `width`/`height` fields (dimensions are then read from each downloaded file instead).
- **Public links.** Anyone with a Google Photos or iCloud album link can view the album. Use a dedicated wallpaper album.
- **API key storage.** The Immich API key is stored in plain text in your config file. Give it read-only scopes.

## Uninstall

```bash
./install.sh --uninstall
```

The config and cache are left in place. Remove them with `rm ~/.config/albumshift.conf` and `rm -rf ~/.cache/albumshift`.

## AI disclosure

This project was developed with [Claude](https://claude.ai), Anthropic's AI assistant. The script, installer, and documentation were written collaboratively in conversation. Google Photos support was run and tested on Nobara Linux (KDE Plasma 6, Wayland); iCloud and Immich support were written without access to real albums, as noted in Caveats. Review the code before running it, as you would any script from the internet.

## Credits

The source integrations are adapted from [eyalgal/album_slideshow](https://github.com/eyalgal/album_slideshow) (MIT), a Home Assistant photo-frame integration:

- `google_scraper.py` documents the Google Photos `snAcKc` request and response layout, the album-key extraction from the share page, and the video marker key.
- `icloud.py` documents both iCloud backends: the legacy shared-streams endpoints and partition-host derivation, and the CloudKit resolve and query flow.
- `immich.py` documents the `search/metadata` paging and thumbnail sizes used for Immich.

## References

- [eyalgal/album_slideshow v0.6.0 release notes](https://github.com/eyalgal/album_slideshow/releases/tag/v0.6.0): moving from the 300-photo share-page limit to `batchexecute` paging
- [Google Photos APIs release notes](https://developers.google.com/photos/support/release-notes): the March 31, 2025 change restricting the Library API to app-created media
- [rclone Google Photos backend docs](https://rclone.org/googlephotos/): confirms rclone can only download photos it uploaded after March 31, 2025
- [rclone forum, Google Photos Picker API](https://forum.rclone.org/t/add-the-new-google-photos-picker-api-to-rclone/47938): Google's announcement of the scope removals and the Picker API replacement
- [rclone forum, Google Photos Ambient API](https://forum.rclone.org/t/google-photos-ambient-api/53876): discussion of Google's display-device API and its limits
