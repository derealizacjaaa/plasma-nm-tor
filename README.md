# plasma-nm-tor

A **Tor toggle button in the KDE Plasma network applet** — next to the
"Keep Open" pin, where it belongs.

- **One click** starts the system Tor daemon; another click stops it.
- **Live bootstrap progress** in the tooltip (read from Tor's control socket).
- **Censored network? Automatic fallback**: if bootstrap makes no progress for
  45 s, the tooltip offers a retry **via obfs4 bridges** — one more click
  switches the running daemon to bridge mode (`SETCONF`, no restart), using
  Tor Browser's built-in bridges or your own.
- **No password prompts**: start/stop goes through systemd D-Bus, authorized by
  a scoped polkit rule (only `tor.service`, only start/stop/restart).
- **Panel icon badge**: while Tor is connected, the Wi-Fi tray icon gets a
  small bridge badge (it replaces the VPN padlock variant — Tor wins), so you
  can see at a glance that Tor is up.
- The button only appears when the module is enabled — the applet is unchanged
  otherwise.

What you get is a **SOCKS proxy at `127.0.0.1:9050`** (like Tor Browser uses).
It does *not* transparently route the whole system through Tor.

## Usage

```nix
{
  inputs.plasma-nm-tor.url = "github:derealizacjaaa/plasma-nm-tor";

  # optional but recommended: use your own nixpkgs
  inputs.plasma-nm-tor.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, plasma-nm-tor, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        plasma-nm-tor.nixosModules.default
        {
          services.plasma-nm-tor = {
            enable = true;
            users = [ "alice" ]; # control-socket access (bootstrap %, bridge mode)
          };
        }
      ];
    };
  };
}
```

Rebuild, then **log out and back in** (the `tor` group membership needs a new
session), and restart plasmashell if it was running.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `services.plasma-nm-tor.enable` | `false` | The whole feature. |
| `services.plasma-nm-tor.users` | `[ ]` | Users added to the `tor` group so the applet can read bootstrap state and switch bridge mode. |
| `services.plasma-nm-tor.polkitGroup` | `"wheel"` | Group allowed to start/stop `tor.service` without a password. |
| `services.plasma-nm-tor.autostart` | `false` | Start Tor at boot instead of on demand. |
| `services.plasma-nm-tor.bridges` | built-in obfs4 list | Bridge lines used by the fallback. |
| `services.plasma-nm-tor.extraBridges` | `[ ]` | Appended to `bridges` (e.g. private bridges from [bridges.torproject.org](https://bridges.torproject.org)). |

## How it works

The flake overlays `kdePackages.plasma-nm` with
[one patch](patches/plasma-nm-tor-button.patch):

- a small `TorStatus` C++ class (QML singleton-style element) that
  - watches `/run/tor/control` (NixOS's permission-gated control socket) for
    bootstrap progress and `UseBridges` state,
  - starts/stops `tor.service` via the systemd D-Bus API,
  - flips the running daemon to bridge mode with
    `SETCONF UseBridges=1 Bridge=…`, reading lines from `/etc/tor/bridges.txt`;
- a high-priority applet action, which Plasma's system tray renders as a small
  icon button in the popup header, next to the configure and pin buttons.

The NixOS module supplies the matching system side: `services.tor` with the
SOCKS client, the control socket, the `lyrebird` pluggable transport preloaded
(so bridge mode needs no daemon restart), the bridges file, and the polkit
rule. By default the unit has no `WantedBy`, so Tor runs **only while the
button is on**.

Because plasma-nm's applet UI is compiled into the plugin, this has to be a
source patch — expect a local plasma-nm rebuild (a few minutes; everything else
comes from the binary cache).

## Compatibility

Developed and tested against **plasma-nm 6.6.6** on NixOS 26.05 with Plasma 6.
The patch touches `applet/main.qml`, `libs/CMakeLists.txt` and adds two files;
if a nixpkgs bump breaks it, rebasing is usually mechanical.

## License

The patch modifies [plasma-nm](https://invent.kde.org/plasma/plasma-nm) and is
licensed the same way: `LGPL-2.1-only OR LGPL-3.0-only OR
LicenseRef-KDE-Accepted-LGPL`. The Nix code is MIT.
