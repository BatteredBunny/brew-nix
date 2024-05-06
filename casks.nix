{ pkgs, lib, brew-api, stdenv, ... }:
let
  hasBinary = cask: lib.hasAttr "binary" (getArtifacts cask);
  hasApp = cask: lib.hasAttr "app" (getArtifacts cask);
  hasPkg = cask: lib.hasAttr "pkg" (getArtifacts cask);

  getBinary = cask: builtins.elemAt (getArtifacts cask).binary 0;
  getApp = cask: builtins.elemAt (getArtifacts cask).app 0;
  getArtifacts = cask: lib.mergeAttrsList cask.artifacts;

  caskToDerivation = cask: stdenv.mkDerivation rec {
    pname = cask.token;
    version = cask.version;

    src = pkgs.fetchurl {
      url = cask.url;
      hash = lib.optionalString (cask.sha256 != "no_check") (builtins.convertHash {
        hash = cask.sha256;
        toHashFormat = "sri";
        hashAlgo = "sha256";
      });
    };

    nativeBuildInputs = with pkgs; [
      undmg
      unzip
      gzip
      _7zz
    ] ++ lib.optional (hasPkg cask) (with pkgs; [
      xar
      cpio
    ]);

    unpackPhase = lib.optionalString (hasPkg cask) ''
      xar -xf $src
      for pkg in $(cat Distribution | grep -oE "#.+\.pkg" | sed -e "s/^#//" -e "s/$/\/Payload/"); do
        zcat $pkg | cpio -i
      done
    '' + lib.optionalString (hasApp cask) ''
      undmg $src || 7zz x $src
    '' + lib.optionalString (hasBinary cask && !hasApp cask && !hasPkg cask) ''
      if [ "$(file --mime-type -b "$src")" == "application/gzip" ]; then
        gunzip $src -c > ${getBinary cask}
      elif [ "$(file --mime-type -b "$src")" == "application/x-mach-binary" ]; then
        cp $src ${getBinary cask}
      fi
    '';

    sourceRoot = lib.optionalString (hasApp cask) (getApp cask);

    installPhase = lib.optionalString (hasPkg cask) ''
      mkdir -p $out/Applications
      cp -R Applications/* $out/Applications/

      if [ -d "Resources" ]; then
        mkdir -p $out/Resources
        cp -R Resources/* $out/Resources/
      fi

      if [ -d "Library" ]; then
        mkdir -p $out/Library
        cp -R Library/* $out/Library/
      fi
    '' + lib.optionalString (hasApp cask) ''
      mkdir -p $out/Applications/${sourceRoot}
      cp -R . $out/Applications/${sourceRoot}
    '' + lib.optionalString (hasBinary cask && !hasApp cask) ''
      mkdir -p $out/bin
      cp -R ./* $out/bin
    '';

    meta = {
      homepage = cask.homepage;
      description = cask.desc;
      platforms = lib.platforms.darwin;
      mainProgram = lib.optionalString (hasBinary cask && !hasApp cask) (getBinary cask);
    };
  };

  casks = builtins.fromJSON (builtins.readFile (brew-api + "/cask.json"));
in
builtins.listToAttrs (builtins.map
  (cask: {
    name = cask.token;
    value = caskToDerivation cask;
  })
  casks)
