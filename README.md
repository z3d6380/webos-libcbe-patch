# webos-libcbe-patch

Bind-mount a patched `libcbe.so` over the web engine on a rooted LG webOS TV, and put the original back with one command.

`libcbe.so` is the Chromium engine behind the built-in browser and every web app. On current sets it is about 154 MB and it lives on a read-only image. LG's signature check covers that image. This tool never writes it. A file on the writable app partition is mounted on top of `/usr/lib/libcbe.so`. Removing the mount shows the signed file again.

The copy inside `libcbe.so` is separate from the system package `lib32-brotli`. Replacing that package does not change the engine.

## What this repo ships

The installer, the rollback, and `builds.txt`.

`builds.txt` names each known `libcbe.so` by its sha256. A row whose patched hash is `-` is recognized, and `apply` refuses it. A patched file is a rebuild of that exact engine with the Brotli decoder fix from [google/brotli@0ed4268](https://github.com/google/brotli/commit/0ed4268) (Brotli 1.0.10, 1.1.1, and 1.2.1). A file built for any other firmware exports the wrong symbols and WebAppMgr will not stay up.

No patched build is published yet. The first row is the engine from firmware 43.21.84 (OLED77C3PUA, webOS 11.2.0, Chrome/132.0.6834.207).

## Install

Root, Homebrew Channel, and SSH. The script is POSIX `sh` and runs under the TV's shell.

```sh
scp libcbe-mount.sh builds.txt lg-tv:/tmp/
ssh lg-tv 'sh /tmp/libcbe-mount.sh install && sh /var/lib/webosbrew/libcbe-mount.sh prepare && sh /var/lib/webosbrew/libcbe-mount.sh status'
```

`install` copies the script to `/var/lib/webosbrew/libcbe-mount.sh`, copies `builds.txt` beside it, and adds an init hook at `/var/lib/webosbrew/init.d/45-libcbe-mount`. The hook returns immediately when the patch is not enabled.

`prepare` copies the live library to `/media/developer/libcbe/original.so`. `/var` on these sets is too small for a second 154 MB file. The app partition is the one with room.

## Apply, once a patched file exists for your hash

Put the published file at `/media/developer/libcbe/patched.so`. Its sha256 has to match the patched column in `builds.txt` for the backup you just took.

```sh
ssh lg-tv 'sh /var/lib/webosbrew/libcbe-mount.sh apply'
```

WebAppMgr keeps the library it already mapped. Start it again so new processes load the mounted file:

```sh
ssh lg-tv 'systemctl restart webapp-mgr'
```

The picture will reload. When the home screen is back and usable:

```sh
ssh lg-tv 'sh /var/lib/webosbrew/libcbe-mount.sh confirm'
```

`webapp-mgr.service` is `Restart=on-failure`. A crash brings it back. A restart you asked for is what picks up the mount.

The init hook runs after WebAppMgr has already started, so a reboot mounts the file and still needs that restart before the new copy is in use. If a boot mounts the file and `confirm` never runs, the next boot drops the mount and the hook.

## Rollback

```sh
ssh lg-tv 'sh /var/lib/webosbrew/libcbe-mount.sh restore && systemctl restart webapp-mgr'
```

`restore` removes the hook and the mount. The signed library is what the path names after that. WebAppMgr still needs a start before it unmaps the patched copy.

## Report an unknown engine

`prepare` prints `This libcbe.so is not in builds.txt` and the sha256. Open an issue with that hash, the model, the webOS version, and the firmware version from the TV's software screen. Leave the patched column as `-` until a rebuild for that exact file exists.

## Commands

| Command | Effect |
|---|---|
| `install` | Copy this script and `builds.txt` into `/var/lib/webosbrew` and add the boot hook. |
| `prepare` | Back up the live library and say whether a patched build is published. |
| `status` | Show the mount, the hashes, and the matching row. |
| `apply` | Mount `patched.so` only when its hash is the published one for this backup. |
| `confirm` | Mark this boot as good so the next boot keeps the mount. |
| `restore` | Remove the mount and the boot hook. |
| `boot` | What the init hook runs. No effect unless `apply` enabled it. |
