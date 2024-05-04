{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    brew-casks = {
      url = "https://formulae.brew.sh/api/cask.json";
      flake = false;
    };
  };

  outputs =
    { nixpkgs
    , flake-utils
    , brew-casks
    , ...
    }:
    flake-utils.lib.eachDefaultSystem (
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

        packages = pkgs.callPackage ./casks.nix { inherit brew-casks; };
      }
    );
}
