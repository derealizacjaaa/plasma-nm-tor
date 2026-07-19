{
  description = "Tor toggle button in the KDE Plasma network applet — one-click Tor with live bootstrap progress and automatic obfs4 bridges fallback";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Overlay factory: patch kdePackages.plasma-nm with the applet features
      # you want. The Tor button is always included; the VPN button (VPN as a
      # header button + hidden from the connection list) is opt-in. The two
      # patches touch disjoint regions and compose in any order.
      mkOverlay =
        {
          vpnButton ? false,
        }:
        final: prev: {
          kdePackages = prev.kdePackages.overrideScope (
            kfinal: kprev: {
              plasma-nm = kprev.plasma-nm.overrideAttrs (old: {
                patches =
                  (old.patches or [ ])
                  ++ [ ./patches/plasma-nm-tor-button.patch ]
                  ++ nixpkgs.lib.optional vpnButton ./patches/plasma-nm-vpn-button.patch;
              });
            }
          );
        };
    in
    {
      # Exposed so the NixOS module can build an overlay from its options.
      lib.mkOverlay = mkOverlay;

      # Tor button only.
      overlays.default = mkOverlay { };
      # Tor button + VPN-as-header-button.
      overlays.withVpnButton = mkOverlay { vpnButton = true; };

      # services.plasma-nm-tor.* — overlay + tor daemon + polkit in one switch.
      nixosModules.default = import ./module.nix self;
      nixosModules.plasma-nm-tor = self.nixosModules.default;

      # `nix build` — the patched plasma-nm, for CI / smoke-testing the patches.
      packages = forAllSystems (
        system:
        let
          pkgsFor = overlay: import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          plasma-nm = (pkgsFor self.overlays.default).kdePackages.plasma-nm;
          plasma-nm-with-vpn = (pkgsFor self.overlays.withVpnButton).kdePackages.plasma-nm;
          default = (pkgsFor self.overlays.default).kdePackages.plasma-nm;
        }
      );
    };
}
