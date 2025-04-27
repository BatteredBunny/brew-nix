{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
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
          ];
        };
      });

      packages = forAllSystems (
        pkgs:
        import ./casks.nix {
          inherit brew-api;
          inherit pkgs;
          lib = pkgs.lib;
          stdenv = pkgs.stdenv;
        };
        }
      );

      overlays.default = final: _: {
        brewCasks = self.packages.${final.system};
      };

      darwinModules.default = lib.modules.importApply ./module.nix { brewCasks = self.overlays.default; };

      checks = forAllSystems (
        pkgs:
        let
          inherit (nix-darwin.packages.${pkgs.stdenv.hostPlatorm}) darwin-rebuild;
        in
        {
          build-examples = pkgs.runCommandLocal "build-examples" { } ''
            export HOME=$(mktemp -d)
            ${darwin-rebuild}/bin/darwin-rebuild build --flake ${self}/examples#somehost
            mkdir "$out"
          '';
        }
      );
    };
}
