{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , brew-api
    , ...
    }:
    {
      overlays.default = final: prev: {
        brewCasks = self.packages.${final.system};
      };
    }
    //
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      rec {
        overlay = final: prev: {
          brewCasks = packages;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixVersions.latest # needed for builtins.convertHash
            wget
          ];
        };

        packages = pkgs.callPackage ./casks.nix { inherit brew-api; };
      }
    ));
}
