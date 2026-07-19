# NixOS module: Tor button in the Plasma network applet.
#
# Wires together everything the patched applet needs:
#   - the plasma-nm overlay (button UI + TorStatus backend),
#   - a system tor daemon with SOCKS proxy, control socket and the lyrebird
#     pluggable transport preloaded (so bridge mode works without a restart),
#   - a bridges file the applet reads when falling back to obfs4,
#   - a polkit rule so the button can start/stop tor.service without a
#     password prompt.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.plasma-nm-tor;

  # Tor Browser's built-in obfs4 bridges (tor-expert-bundle pt_config.json).
  builtinBridges = [
    "obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0"
    "obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0"
    "obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0"
    "obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0"
    "obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0"
    "obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1"
    "obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1"
  ];
in
{
  options.services.plasma-nm-tor = {
    enable = lib.mkEnableOption "Tor toggle button in the Plasma network applet";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Users who get access to Tor's control socket (added to the `tor`
        group). Without this the button still starts/stops the daemon, but
        cannot show bootstrap progress or switch to bridges. Takes effect
        after the user logs in again.
      '';
    };

    polkitGroup = lib.mkOption {
      type = lib.types.str;
      default = "wheel";
      description = ''
        Group allowed to start/stop `tor.service` from the applet without a
        password prompt.
      '';
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start Tor at boot. By default the daemon only runs while toggled on
        from the applet.
      '';
    };

    bridges = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = builtinBridges;
      description = ''
        Bridge lines the applet switches to when a direct connection stalls
        (via SETCONF, no daemon restart). Defaults to Tor Browser's built-in
        obfs4 bridges; heavily censored networks will need private ones from
        <https://bridges.torproject.org>.
      '';
    };

    extraBridges = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Bridge lines appended to `bridges`.";
    };

    vpnButton.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also patch in a VPN button next to the Tor one: NetworkManager
        VPN/WireGuard connections become a single header button (toggle, with
        the provider and IPv4 in the tooltip) instead of entries in the
        connection list. Independent of the Tor feature; enable if you want
        both buttons.
      '';
    };

    vpnConfigSwap = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also patch in on-the-fly VPN configuration swapping: expanding a
          VPN/WireGuard connection in the applet lists the configuration
          files (`.ovpn`, `.conf`, `.wg`, `.pcf`) found in
          `~/.config/plasma-nm-vpn-configs` and `/etc/plasma-nm/vpn-configs`;
          clicking one imports it through NetworkManager's VPN plugins,
          overwrites the connection's settings in place (name and UUID are
          kept) and reconnects the tunnel.

          Note: the swap list lives in the connection-list entry, which
          `vpnButton.enable` hides — with both enabled the swap UI is
          unreachable.
        '';
      };

      directory = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/persist/vpn-configs";
        description = ''
          Directory symlinked to `/etc/plasma-nm/vpn-configs` for the config
          swap feature. Use a plain string path outside the Nix store — VPN
          configs usually embed private keys, which must not end up
          world-readable in `/nix/store`. Per-user files can instead go into
          `~/.config/plasma-nm-vpn-configs` without any Nix wiring.
        '';
      };
    };

    transparent.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Route the whole system through Tor transparently while the daemon is
        on — no per-app proxy configuration needed. Installs a fail-closed
        nftables kill-switch (bound to `tor.service`, so it appears and
        disappears with the button): all TCP is redirected to Tor's TransPort,
        DNS to its DNSPort, and everything that Tor cannot carry (other UDP,
        all IPv6) is dropped rather than leaked. LAN and loopback stay direct.

        Trade-off: UDP-only and IPv6-only apps stop working while Tor is on.
        That is the price of no leaks.
      '';
    };

    exclusiveWithVpn = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Treat Tor and NetworkManager VPN/WireGuard connections as mutually
        exclusive: starting Tor tears down any active VPN, and bringing a VPN
        up stops Tor. Prevents the broken routing you would otherwise get from
        transparent Tor stacked on a VPN tunnel.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (self.lib.mkOverlay {
        vpnButton = cfg.vpnButton.enable;
        vpnConfigSwap = cfg.vpnConfigSwap.enable;
      })
    ];

    warnings = lib.optional (cfg.vpnButton.enable && cfg.vpnConfigSwap.enable) ''
      services.plasma-nm-tor: vpnButton.enable hides VPN connections from the
      applet's connection list, which is where vpnConfigSwap's file list is
      shown — with both enabled the config swap UI is unreachable.
    '';

    environment.etc."plasma-nm/vpn-configs" = lib.mkIf (cfg.vpnConfigSwap.directory != null) {
      source = cfg.vpnConfigSwap.directory;
    };

    # Icons: the bridge glyph for the applet button, plus Wi-Fi icons with a
    # small bridge badge shown in the panel while Tor is on. The badged icons
    # use a distinct "wifitor-" namespace on purpose: if we named them
    # "network-wireless-N-tor", Plasma's desktop-theme lookup would strip the
    # unknown "-tor" suffix back to "network-wireless-N" and render the plain
    # base Wi-Fi icon, never reaching our hicolor badge. "wifitor-" has no
    # base in the desktop theme, so lookup falls through to these icons.
    environment.systemPackages = [
      (pkgs.runCommand "plasma-nm-tor-icons" { } ''
        dir=$out/share/icons/hicolor/scalable/status
        install -Dm644 ${./icons/network-tor-bridge.svg} $dir/network-tor-bridge.svg

        # wifitor-<strength>(-symbolic): Wi-Fi arcs lit per strength + bridge
        gen() { # gen <strength> <o1> <o2> <o3>
          sed -e "s/@O1@/$2/" -e "s/@O2@/$3/" -e "s/@O3@/$4/" \
            ${./icons/wifi-tor-template.svg} > $dir/wifitor-$1.svg
          cp $dir/wifitor-$1.svg $dir/wifitor-$1-symbolic.svg
        }
        gen 0   0.35 0.35 0.35
        gen 20  1    0.35 0.35
        gen 40  1    0.35 0.35
        gen 60  1    1    0.35
        gen 80  1    1    1
        gen 100 1    1    1
      '')
    ];

    services.tor = {
      enable = true;
      client.enable = true; # SOCKS proxy on 127.0.0.1:9050
      controlSocket.enable = true; # /run/tor/control — applet reads state here
      # Whole-system routing: TransPort 9040 + DNSPort 9053 + AutomapHosts.
      client.transparentProxy.enable = cfg.transparent.enable;
      client.dns.enable = cfg.transparent.enable;
      settings = {
        # Transport ready from the start so SETCONF UseBridges=1 (the applet's
        # stall fallback) works without restarting the daemon.
        ClientTransportPlugin = "meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ${pkgs.obfs4}/bin/lyrebird";
      }
      // lib.optionalAttrs cfg.transparent.enable {
        VirtualAddrNetworkIPv4 = "10.192.0.0/10";
      };
    };

    systemd.services.tor.wantedBy = lib.mkIf (!cfg.autostart) (lib.mkForce [ ]);

    environment.etc."tor/bridges.txt".text = lib.concatMapStrings (b: b + "\n") (
      cfg.bridges ++ cfg.extraBridges
    );

    users.users = lib.genAttrs cfg.users (name: {
      extraGroups = [ "tor" ];
    });

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.isInGroup("${cfg.polkitGroup}") &&
            action.lookup("unit") == "tor.service") {
          var verb = action.lookup("verb");
          if (verb == "start" || verb == "stop" || verb == "restart") {
            return polkit.Result.YES;
          }
        }
      });
    '';

    # ── Transparent routing kill-switch ────────────────────────────────────
    # A companion unit bound to tor.service: it comes up and down with the
    # Tor button and installs/removes a fail-closed nftables ruleset. tor's
    # own traffic (skuid tor) and LAN/loopback stay direct; new TCP is
    # redirected to TransPort, DNS to DNSPort, and anything Tor cannot carry
    # is dropped. Uses private tables, so it coexists with the main firewall.
    systemd.services.tor-transparent = lib.mkIf cfg.transparent.enable {
      description = "Transparent Tor routing (nftables kill-switch)";
      bindsTo = [ "tor.service" ];
      partOf = [ "tor.service" ];
      after = [ "tor.service" ];
      wantedBy = [ "tor.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "tor-transparent-up" ''
          ${lib.optionalString cfg.exclusiveWithVpn ''
            # Auto-switch: tearing the VPN down before Tor takes over routing.
            for u in $(${pkgs.networkmanager}/bin/nmcli -t -f UUID,TYPE connection show --active \
                        | ${pkgs.gnugrep}/bin/grep -E ':(vpn|wireguard)$' \
                        | ${pkgs.coreutils}/bin/cut -d: -f1); do
              ${pkgs.networkmanager}/bin/nmcli connection down uuid "$u" || true
            done
          ''}
          ${pkgs.nftables}/bin/nft -f - <<'RULES'
          table ip tor_nat {
            chain output {
              type nat hook output priority -100; policy accept;
              meta skuid tor return
              oifname "lo" return
              ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 } return
              meta l4proto udp udp dport 53 redirect to :9053
              meta l4proto tcp tcp dport 53 redirect to :9053
              meta l4proto tcp redirect to :9040
            }
          }
          table ip tor_filter {
            chain output {
              type filter hook output priority 0; policy drop;
              meta skuid tor accept
              oifname "lo" accept
              ct state established,related accept
              ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 } accept
              meta l4proto tcp accept
            }
          }
          table ip6 tor_filter6 {
            chain output {
              type filter hook output priority 0; policy drop;
              oifname "lo" accept
              ip6 daddr { ::1, fe80::/10, fc00::/7 } accept
            }
          }
          RULES
        '';
        ExecStop = pkgs.writeShellScript "tor-transparent-down" ''
          ${pkgs.nftables}/bin/nft delete table ip tor_nat 2>/dev/null || true
          ${pkgs.nftables}/bin/nft delete table ip tor_filter 2>/dev/null || true
          ${pkgs.nftables}/bin/nft delete table ip6 tor_filter6 2>/dev/null || true
        '';
      };
    };

    # ── VPN → Tor half of the auto-switch ──────────────────────────────────
    # Bringing up a VPN/WireGuard connection stops Tor (the other direction —
    # Tor → VPN — is handled above / by tor.service startup below).
    networking.networkmanager.dispatcherScripts = lib.mkIf cfg.exclusiveWithVpn [
      {
        type = "basic";
        source = pkgs.writeShellScript "tor-vpn-exclusive" ''
          action="$2"
          if [ "$action" = "vpn-up" ]; then
            ${pkgs.systemd}/bin/systemctl stop tor.service || true
            exit 0
          fi
          if [ "$action" = "up" ] && [ -n "$CONNECTION_UUID" ]; then
            t=$(${pkgs.networkmanager}/bin/nmcli -t -f connection.type connection show "$CONNECTION_UUID" 2>/dev/null | ${pkgs.coreutils}/bin/cut -d: -f2)
            case "$t" in
              *wireguard*|*vpn*) ${pkgs.systemd}/bin/systemctl stop tor.service || true ;;
            esac
          fi
        '';
      }
    ];

    # Tor → VPN when transparent routing is off (with it on, tor-transparent's
    # ExecStart already dropped the VPN). Runs as root so nmcli has NM rights.
    systemd.services.tor-vpn-exclusive = lib.mkIf (cfg.exclusiveWithVpn && !cfg.transparent.enable) {
      description = "Disconnect VPN/WireGuard when Tor starts";
      bindsTo = [ "tor.service" ];
      after = [ "tor.service" ];
      wantedBy = [ "tor.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "tor-drop-vpn" ''
          for u in $(${pkgs.networkmanager}/bin/nmcli -t -f UUID,TYPE connection show --active \
                      | ${pkgs.gnugrep}/bin/grep -E ':(vpn|wireguard)$' \
                      | ${pkgs.coreutils}/bin/cut -d: -f1); do
            ${pkgs.networkmanager}/bin/nmcli connection down uuid "$u" || true
          done
        '';
      };
    };
  };
}
