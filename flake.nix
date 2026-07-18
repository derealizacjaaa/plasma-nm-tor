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
    in
    {
      # Patches kdePackages.plasma-nm so the network applet grows a Tor button.
      overlays.default = final: prev: {
        kdePackages = prev.kdePackages.overrideScope (
          kfinal: kprev: {
            plasma-nm = kprev.plasma-nm.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [ ./patches/plasma-nm-tor-button.patch ];
            });
          }
        );
      };

      # services.plasma-nm-tor.* — overlay + tor daemon + polkit in one switch.
      nixosModules.default = import ./module.nix self;
      nixosModules.plasma-nm-tor = self.nixosModules.default;

      # `nix build` — the patched plasma-nm, for CI / smoke-testing the patch.
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          plasma-nm = pkgs.kdePackages.plasma-nm;
          default = pkgs.kdePackages.plasma-nm;
        }
      );
    };
}
