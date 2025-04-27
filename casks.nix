{
  pkgs,
  lib ? pkgs.lib,
  brew-api,
  stdenv ? pkgs.stdenv,
  ...
}:
let
  getName = cask: builtins.elemAt cask.name 0;

  getBinary = cask: builtins.elemAt (getArtifacts cask).binary 0;
  getApp = cask: builtins.elemAt (getArtifacts cask).app 0;
  getArtifacts = cask: lib.mergeAttrsList cask.artifacts;

  caskToDerivation =
    cask:
    let
      isBinary = lib.hasAttr "binary" (getArtifacts cask);
      isApp = lib.hasAttr "app" (getArtifacts cask);
      isPkg = lib.hasAttr "pkg" (getArtifacts cask);
    in
    stdenv.mkDerivation (finalAttrs: {
      pname = cask.token;
      inherit (cask) version;

      src = pkgs.fetchurl {
        inherit (cask) url;
        sha256 = lib.optionalString (cask.sha256 != "no_check") cask.sha256;
      };

      nativeBuildInputs =
        with pkgs;
        [
          undmg
          unzip
          gzip
          _7zz
          makeWrapper
        ]
        ++ lib.optional isPkg (
          with pkgs;
          [
            xar
            cpio
          ]
        );

      unpackPhase =
        if isPkg then
          ''
            xar -xf $src
            for pkg in $(cat Distribution | grep -oE "#.+\.pkg" | sed -e "s/^#//" -e "s/$/\/Payload/"); do
              zcat $pkg | cpio -i
            done
          ''
        else if isApp then
          ''
            undmg $src || 7zz x -snld $src
          ''
        else if isBinary then
          ''
            if [ "$(file --mime-type -b "$src")" == "application/gzip" ]; then
              gunzip $src -c > ${getBinary cask}
            elif [ "$(file --mime-type -b "$src")" == "application/x-mach-binary" ]; then
              cp $src ${getBinary cask}
            fi
          ''
        else
          "";

      sourceRoot = lib.optionalString isApp (getApp cask);

      # Patching shebangs invalidates code signing
      dontPatchShebangs = true;

      installPhase =
        if isPkg then
          ''
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
          ''
        else if isApp then
          ''
            mkdir -p "$out/Applications/${finalAttrs.sourceRoot}"
            cp -R . "$out/Applications/${finalAttrs.sourceRoot}"

            if [[ -e "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${getName cask}" ]]; then
              makeWrapper "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${getName cask}" $out/bin/${cask.token}
            elif [[ -e "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${lib.removeSuffix ".app" finalAttrs.sourceRoot}" ]]; then
              makeWrapper "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${lib.removeSuffix ".app" finalAttrs.sourceRoot}" $out/bin/${cask.token}
            fi
          ''
        else if (isBinary && !isApp) then
          ''
            mkdir -p $out/bin
            cp -R ./* $out/bin
          ''
        else
          "";

      meta = {
        inherit (cask) homepage;
        description = cask.desc;
        platforms = lib.platforms.darwin;
        mainProgram = if (isBinary && !isApp) then (getBinary cask) else cask.token;
      };
    });

  casks = lib.importJSON (brew-api + "/cask.json");
in
lib.listToAttrs (
  builtins.map (cask: {
    name = cask.token;
    value = caskToDerivation cask;
  }) casks
)
