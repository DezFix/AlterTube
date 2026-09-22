<hr>
<p align="center"><img src="assets/logo.png" width="150"></p>
<h2 align="center"><b>AlterTube</b></h2>
<h4 align="center">
A lightweight YouTube client: TikTok-style Shorts feed + music mode, no ads.</h4>
<hr>

> ⚠️ Early rebrand stage: based on PipePipe v5.4.0-beta, package `app.wre.altertube`.
> F-Droid listing is planned but not submitted yet — install from GitHub Releases for now.

## Where we are going

* **YouTube only** — extra services (BiliBili, NicoNico, SoundCloud, PeerTube) are being removed
* **Shorts feed** — fullscreen vertical player, TikTok-style
* **Music mode** — audio-only playback with background service
* **Cookie login** — access to restricted content, configurable per-use ("Cookie Functions")
* No ads, no trackers, GPL-3.0

## Features (inherited from PipePipe)

#### YouTube Enhancements
* SponsorBlock skipping for sponsored segments
* ReturnYouTubeDislike integration
* Original (non-localized) titles
* Login via cookie for restricted content

#### Media
* Background playback / music player mode
* AV1 & VP9 codecs
* Danmaku-style live chat overlay

#### Filtering & Playback
* Advanced search filters, keyword/channel filters
* Swipe-to-seek, fullscreen gestures, long-press speed-up, sleep timer
* Full-playlist downloads, search & sort in playlists and history

## Repositories

* [AlterTube](https://github.com/DezFix/AlterTube) — this superproject
* [AlterTubeClient](https://github.com/DezFix/AlterTubeClient) — the Android app
* [AlterTubeExtractor](https://github.com/DezFix/AlterTubeExtractor) — the stream extractor

## Lineage / thanks

AlterTube stands on the shoulders of giants. Full credit to everyone before us:

* [TeamNewPipe](https://github.com/TeamNewPipe) — [NewPipe](https://github.com/TeamNewPipe/NewPipe)
  and [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor): the original idea,
  protocol research and extractor architecture (GPL-3.0)
* [InfinityLoop1308](https://github.com/InfinityLoop1308) — [PipePipe](https://github.com/InfinityLoop1308/PipePipe):
  the hard fork we are based on (faster release cycle, SponsorBlock, RYD, SABR support)
* [Priveetee](https://github.com/Priveetee) — SABR research and implementation
  ([Docs-PipePipe](https://priveetee.github.io/Docs-PipePipe))
* [AioiLight](https://github.com/AioiLight) — NicoNico service code
* [SponsorBlock](https://sponsor.ajay.app/) — crowdsourced segment database
* [ReturnYouTubeDislike](https://returnyoutubedislike.com/) — restored dislike counts

This fork must stay under **GPL-3.0**, see `LICENSE`.

## Contribute

Issues and PRs are welcomed. Please note that we will **NOT** accept new service requests —
AlterTube is YouTube-only by design.

## License

GNU General Public License v3.0 or later.
