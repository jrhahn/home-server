# Migrating Google Photos to Immich

This guide moves an existing Google Photos library (e.g. from a Pixel phone)
into the self-hosted Immich instance at:

```text
http://photos.home.arpa
```

Keep Tailscale connected while uploading and while using the phone app.

## Why Not Just the Immich App

The Immich mobile app only backs up media that is physically present on the
phone. Photos that Google Photos has offloaded to the cloud ("free up space")
are no longer on the device in full resolution. To migrate the *complete*
library, export it from Google with Takeout instead.

## Migration Order (Important)

Do the steps in this order so Google Photos stays a safety net until the
migration is verified:

1. **Now: enable Immich app backup.** A requested Takeout export is frozen at
   request time, so any photo taken *after* that is not included. Turning on
   Immich backup now closes that gap for new photos.
2. **Keep Google Photos backup ON** until the Takeout is downloaded, imported,
   and spot-checked in Immich.
3. **Only then: disable Google Photos automatic backup.**

Running both backups in parallel for a few days is fine; it is just redundancy.

## Step 1 - Request a Google Takeout

1. Open <https://takeout.google.com>.
2. Deselect everything, then select only **Google Photos**.
3. Export as `.zip` with a part size of **50 GB** (fewer files to juggle).
4. Start the export. Google emails download links after hours to days.
5. Download every ZIP part to the server, or to a machine with Tailscale access.

Takeout writes a `.json` sidecar next to each photo containing the capture date,
GPS location, and album membership. Do not discard these files; they are needed
to restore correct metadata.

## Step 2 - Use immich-go

The official Immich CLI ignores the Takeout JSON sidecars, which leaves photos
sorted by import date instead of capture date. Use
[`immich-go`](https://github.com/simulot/immich-go) instead: it reads the JSON,
fixes date and GPS metadata, and recreates Google albums in Immich.

1. Download a release binary from
   <https://github.com/simulot/immich-go/releases>.
2. Create an Immich API key: **Account Settings -> API Keys**.

## Step 3 - Upload

`immich-go` reads the ZIP parts directly, no manual extraction needed:

```bash
immich-go upload from-google-photos \
  --server=http://photos.home.arpa \
  --api-key=YOUR_API_KEY \
  takeout-*.zip
```

Run this on the server or a well-connected machine (Tailscale works from a
laptop too). Duplicates are detected automatically, so the command is safe to
re-run if it is interrupted.

## Step 4 - Verify, Then Cut Over

1. In Immich, spot-check: total count, albums, timeline date sorting, and GPS
   pins on the map.
2. Trigger background work under **Administration -> Jobs** (thumbnails,
   smart search / ML, face detection) after a large import.
3. Once verified, disable automatic backup in the Google Photos app.

## Check Free Space First

Originals are stored under `/srv/immich-originals`. Per the storage layout this
is still on the SSD until a dedicated HDD is added later. Google libraries are
easily several hundred GB, so confirm there is room before starting:

```bash
df -h /srv
```

See [immich-getting-started.md](immich-getting-started.md) for the storage
layout and how to move originals to a future HDD.
