{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      brew-api,
      nix-darwin,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            wget
            python3
            ruff
            ty
          ];
        };
      });

      packages = forAllSystems (
        pkgs:
        import ./casks.nix {
          inherit brew-api;
          inherit pkgs;
        }
      );

      overlays.default = final: _: {
        brewCasks = self.packages.${final.stdenv.hostPlatform.system};
      };

      darwinModules.default = lib.modules.importApply ./module.nix { brewCasks = self.overlays.default; };

      checks = forAllSystems (pkgs: {
        build-examples =
          ((import ./examples/flake.nix).outputs {
            inherit nix-darwin;
            brew-nix = self;
          }).darwinConfigurations.somehost.system;
      });
    };
}
