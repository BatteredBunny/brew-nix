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
    {
      self,
      nixpkgs,
      flake-utils,
      brew-api,
      nix-darwin,
      ...
    }:
    rec {
      overlays.default = final: prev: {
        brewCasks = self.packages.${final.system};
      };
      darwinModules.default = (import ./module.nix) { brewCasks = overlays.default; };
    }
    // (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            wget
          ];
        };

        packages = import ./casks.nix {
          inherit brew-api;
          inherit pkgs;
          lib = pkgs.lib;
          stdenv = pkgs.stdenv;
        };

        # XXX: the check only runs successful on Darwin systems, but is provided for "eachDefaultSystem",
        #      including Linux; probably best to limit systems in general, since `casks.nix` is obviously
        #      tailored towards Darwin systems and not Linux or anything else
        checks.build-examples =
          let
            # override darwin-rebuild to use correct Nix version
            darwin-rebuild = nix-darwin.packages.${system}.darwin-rebuild;
          in
          pkgs.runCommandLocal "build-examples" { } ''
            export HOME=$(mktemp -d)
            ${darwin-rebuild}/bin/darwin-rebuild build --flake ${self}/examples#somehost
            mkdir "$out"
          '';
      }
    ));
}
