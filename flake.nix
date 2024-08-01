{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
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
    { self
    , nixpkgs
    , flake-utils
    , brew-api
    , nix-darwin
    , ...
    }:
    rec {
      overlays.default = final: prev: {
        brewCasks = self.packages.${final.system};
      };
      darwinModules.default = (import ./module.nix) { brewCasks = overlays.default; };
    }
    //
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixVersions.latest # needed for builtins.convertHash
            wget
          ];
        };

        packages = import ./casks.nix { inherit brew-api; inherit pkgs; lib = pkgs.lib; stdenv = pkgs.stdenv; };

        checks.build-examples = let
          # override darwin-rebuild to use correct Nix version
          darwin-rebuild-path = (nix-darwin.packages.${system}.darwin-rebuild.overrideAttrs (prev: { path = (pkgs.nixVersions.nix_2_19) + "/bin:" + prev.path; }));
        in
          pkgs.runCommandLocal "build-examples" {} ''
            export HOME=$(mktemp -d)
            ${darwin-rebuild-path}/bin/darwin-rebuild build --flake ${self}/examples#somehost
            mkdir "$out"
          '';
      }
    ));
}
