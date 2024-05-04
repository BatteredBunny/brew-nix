{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    cask = {
      url = "https://formulae.brew.sh/api/cask.json";
      flake = false;
    };
  };

  outputs =
    { nixpkgs
    , flake-utils
    , cask
    , ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        caskToDerivation = cask: pkgs.stdenv.mkDerivation rec {
          pname = cask.token;
          version = cask.version;

          # TODO: handle if its a zip somehow
          src = pkgs.fetchurl {
            url = cask.url;
            hash = builtins.convertHash { hash = cask.sha256; toHashFormat = "sri"; hashAlgo = "sha256"; };
          };

          nativeBuildInputs = with pkgs; [
            undmg unzip
          ];

          sourceRoot = builtins.elemAt (pkgs.lib.mergeAttrsList cask.artifacts).app 0;

          installPhase = ''
            mkdir -p $out/Applications/${sourceRoot}
            cp -R . $out/Applications/${sourceRoot}

            # mkdir -p $out/bin
            # ln -s $out/Applications/${sourceRoot}/Contents/MacOS/${builtins.elemAt cask.name 0} $out/bin
          '';

          meta = {
            homepage = cask.homepage;
            description = cask.desc;
            platforms = pkgs.lib.platforms.darwin;
            # mainProgram = builtins.elemAt cask.name 0;
          };
        };

        casks = builtins.fromJSON (builtins.readFile cask);
      in
      rec {
        overlay = final: prev: packages;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixVersions.latest # needed for builtins.convertHash
          ];
        };

        packages = builtins.listToAttrs (builtins.map
          (cask: {
            name = cask.token;
            value = caskToDerivation cask;
          })
          casks);
      }
    );
}
