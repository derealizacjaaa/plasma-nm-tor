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
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ self.overlays.default ];

    services.tor = {
      enable = true;
      client.enable = true; # SOCKS proxy on 127.0.0.1:9050
      controlSocket.enable = true; # /run/tor/control — applet reads state here
      settings = {
        # Transport ready from the start so SETCONF UseBridges=1 (the applet's
        # stall fallback) works without restarting the daemon.
        ClientTransportPlugin = "meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ${pkgs.obfs4}/bin/lyrebird";
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
  };
}
