{
  pkgs,
  lib ? pkgs.lib,
  brew-api,
  stdenvNoCC ? pkgs.stdenvNoCC,
  ...
}: let
  getName = cask: lib.lists.elemAt cask.name 0;
  getBinary = artifacts: lib.lists.elemAt artifacts.binary 0;
  getApp = artifacts: lib.lists.elemAt artifacts.app 0;

  getVariationData = cask: variation:
    if cask ? variations && lib.attrsets.hasAttr variation cask.variations
    then cask.variations."${variation}"
    else throw "Variation '${variation}' not found for ${cask.token}. Available: ${toString (lib.attrsets.attrNames (cask.variations or {}))}";

  caskToDerivation = cask: {variation ? null}: let
    specificVariationData =
      if variation != null
      then getVariationData cask variation
      else {};

    defaultCaskData = {
      url = cask.url or null;
      sha256 = cask.sha256 or null;
      version = cask.version or null;
      artifacts = cask.artifacts or [];
    };

    selectedData = defaultCaskData // specificVariationData;

    inherit (selectedData) url sha256 version;
    artifacts = lib.attrsets.mergeAttrsList selectedData.artifacts;

    isBinary = lib.attrsets.hasAttr "binary" artifacts;
    isApp = lib.attrsets.hasAttr "app" artifacts;
    isPkg = lib.attrsets.hasAttr "pkg" artifacts;
  in
    stdenvNoCC.mkDerivation (finalAttrs: {
      pname = cask.token;
      inherit version;

      src = pkgs.fetchurl {
        inherit url;
        sha256 = lib.strings.optionalString (sha256 != null && sha256 != "no_check") sha256;
      };

      nativeBuildInputs = with pkgs;
        [
          undmg
          unzip
          gzip
          _7zz
          makeWrapper
        ]
        ++ lib.lists.optional isPkg (
          with pkgs; [
            xar
            cpio
            fd
          ]
        );

      unpackPhase =
        if isPkg
        then ''
          xar -xf $src
          for pkg in $(cat Distribution | grep -oE "#.+\.pkg" | sed -e "s/^#//" -e "s/$/\/Payload/"); do
            zcat $pkg | cpio -i
          done
        ''
        else if isApp
        then ''
          case "$src" in
            *.dmg)            undmg "$src" ;;
            *.zip)            unzip "$src" ;;
            *.tar.gz|*.tgz)   tar -xzf "$src" ;;
            *.tar.xz)         tar -xJf "$src" ;;
            *.tar.bz2|*.tbz2) tar -xjf "$src" ;;
            *)                7zz x -snld "$src" ;;
          esac
        ''
        else if isBinary
        then ''
          case "$src" in
            *.zip)            unzip "$src" ;;
            *.tar.gz|*.tgz)   tar -xzf "$src" ;;
            *.tar.xz)         tar -xJf "$src" ;;
            *.tar.bz2|*.tbz2) tar -xjf "$src" ;;
            *.tar)            tar -xf "$src" ;;
            *)
              mime="$(file --mime-type -b "$src")"
              if [ "$mime" == "application/gzip" ]; then
                gunzip $src -c > ${getBinary artifacts}
              elif [ "$mime" == "application/x-mach-binary" ]; then
                cp $src ${getBinary artifacts}
              else
                7zz x -snld "$src"
              fi
              ;;
          esac
        ''
        else "";

      sourceRoot = lib.strings.optionalString isApp (getApp artifacts);

      # Patching shebangs invalidates code signing
      dontPatchShebangs = true;

      installPhase =
        if isPkg
        then ''
          if [ -d "Applications" ]; then
            mkdir -p $out/Applications
            cp -R Applications/* $out/Applications/
          fi

          if [ -n "$(fd -d 1 -t d '\.app$' .)" ]; then
            mkdir -p $out/Applications
            cp -R *.app $out/Applications/
          fi

          if [ -d "Library" ]; then
            mkdir -p $out/Library
            cp -R Library/* $out/Library/
          fi
        ''
        else if isApp
        then ''
          mkdir -p "$out/Applications/${finalAttrs.sourceRoot}"
          cp -R . "$out/Applications/${finalAttrs.sourceRoot}"

          if [[ -e "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${getName cask}" ]]; then
            makeWrapper "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${getName cask}" $out/bin/${cask.token}
          elif [[ -e "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${lib.strings.removeSuffix ".app" finalAttrs.sourceRoot}" ]]; then
            makeWrapper "$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS/${lib.strings.removeSuffix ".app" finalAttrs.sourceRoot}" $out/bin/${cask.token}
          fi
        ''
        else if (isBinary && !isApp)
        then ''
          mkdir -p $out/bin
          install -m755 ${getBinary artifacts} $out/bin/
        ''
        else "";

      meta = {
        inherit (cask) homepage;
        description = cask.desc;
        platforms = lib.platforms.darwin;
        mainProgram =
          if (isBinary && !isApp)
          then (getBinary artifacts)
          else cask.token;
      };
    });

  casks = lib.trivial.importJSON (brew-api + "/cask.json");
in
  lib.attrsets.listToAttrs (
    lib.lists.map (cask: {
      name = cask.token;
      value = lib.customisation.makeOverridable (caskToDerivation cask) {};
    })
    casks
  )