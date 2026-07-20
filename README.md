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
| `services.plasma-nm-tor.vpnButton.enable` | `false` | Also add a VPN button: NM VPN/WireGuard connections become a header button (toggle + provider/IPv4 tooltip) instead of connection-list entries. |
| `services.plasma-nm-tor.vpnConfigSwap.enable` | `false` | On-the-fly VPN config swapping: adds a dedicated "VPN" page to System Settings (next to Wi-Fi & Networking) listing config files from the watched directories; one click imports the file, overwrites the chosen connection in place and reconnects. |
| `services.plasma-nm-tor.vpnConfigSwap.directory` | `null` | Directory symlinked to `/etc/plasma-nm/vpn-configs`. Keep it outside the Nix store — VPN configs embed private keys. Per-user files go in `~/.config/plasma-nm-vpn-configs` with no Nix wiring. |
| `services.plasma-nm-tor.users` | `[ ]` | Users added to the `tor` group so the applet can read bootstrap state and switch bridge mode. |
| `services.plasma-nm-tor.polkitGroup` | `"wheel"` | Group allowed to start/stop `tor.service` without a password. |
| `services.plasma-nm-tor.autostart` | `false` | Start Tor at boot instead of on demand. |
| `services.plasma-nm-tor.bridges` | built-in obfs4 list | Bridge lines used by the fallback. |
| `services.plasma-nm-tor.extraBridges` | `[ ]` | Appended to `bridges` (e.g. private bridges from [bridges.torproject.org](https://bridges.torproject.org)). |

## How it works

The flake overlays `kdePackages.plasma-nm` with
[the Tor patch](patches/plasma-nm-tor-button.patch) (and, opt-in,
[the VPN button patch](patches/plasma-nm-vpn-button.patch) and
[the VPN config swap patch](patches/plasma-nm-vpn-config-swap.patch);
the patches touch disjoint regions and compose in any order):

- a small `TorStatus` C++ class (QML singleton-style element) that
  - watches `/run/tor/control` (NixOS's permission-gated control socket) for
    bootstrap progress and `UseBridges` state,
  - starts/stops `tor.service` via the systemd D-Bus API,
  - flips the running daemon to bridge mode with
    `SETCONF UseBridges=1 Bridge=…`, reading lines from `/etc/tor/bridges.txt`;
- a high-priority applet action, which Plasma's system tray renders as a small
  icon button in the popup header, next to the configure and pin buttons.

With `vpnConfigSwap.enable`, a `VpnConfigs` C++ class watches
`~/.config/plasma-nm-vpn-configs` and `/etc/plasma-nm/vpn-configs` for
`.ovpn`/`.conf`/`.wg`/`.pcf` files, and a new System Settings module
(`kcm_vpnconfigs`, the "VPN" sidebar entry under Wi-Fi & Networking) lists
them per VPN/WireGuard connection. Clicking a file imports it through
NetworkManager's own VPN editor plugins (the same machinery
`nmcli connection import` uses; WireGuard goes through libnm directly),
overwrites the connection's settings while keeping its name, UUID and DNS
priority (leak-protection tuning like `ipv4.dns-priority=-10` survives the
swap; a type change — e.g. OpenVPN → WireGuard — re-creates the connection
under the same name), records the source file in the connection's `user`
setting (shown as a ✓), and restarts the tunnel. The applet itself stays
stock apart from the Tor button.

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
