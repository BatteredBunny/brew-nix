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
    let
      # less than 2.19 does not do it, but let's not go overboard with latest version
      nixRequiredVersion = rec {
        versionSatisfiesRequirement = pkgs: nix: (builtins.compareVersions nix.version pkgs.nixVersions.nix_2_19.version) >= 0;
        package = pkgs:
          if versionSatisfiesRequirement pkgs pkgs.nix
          then pkgs.nix
          else pkgs.nixVersions.nix_2_19;
        message = "Nix version 2.19 is required at least.";
      };
    in
    rec {
      overlays.default = final: prev: {
        brewCasks = self.packages.${final.system};
      };
      darwinModules.default = (import ./module.nix) { brewCasks = overlays.default; inherit nixRequiredVersion; };
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
            (nixRequiredVersion.package pkgs)
            wget
          ];
        };

        packages = import ./casks.nix { inherit brew-api; inherit pkgs; lib = pkgs.lib; stdenv = pkgs.stdenv; };

        # XXX: the check only runs successful on Darwin systems, but is provided for "eachDefaultSystem",
        #      including Linux; probably best to limit systems in general, since `casks.nix` is obviously
        #      tailored towards Darwin systems and not Linux or anything else
        checks.build-examples = let
          # override darwin-rebuild to use correct Nix version
          # XXX: There seems to be some incompatibility of lock-files between Nix versions.
          #      This error occurs when a different Nix version is used to build the system than was used
          #      to lock the flake in `examples/`: https://github.com/NixOS/nix/issues/10815
          darwin-rebuild-path = (nix-darwin.packages.${system}.darwin-rebuild.overrideAttrs (prev: { path = (nixRequiredVersion.package pkgs) + "/bin:" + prev.path; }));
        in
          pkgs.runCommandLocal "build-examples" {} ''
            export HOME=$(mktemp -d)
            ${darwin-rebuild-path}/bin/darwin-rebuild build --flake ${self}/examples#somehost
            mkdir "$out"
          '';
      }
    ));
}
