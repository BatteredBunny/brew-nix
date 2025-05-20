{
  pkgs,
  lib ? pkgs.lib,
  brew-api,
  stdenvNoCC ? pkgs.stdenvNoCC,
  currentMacosName ? "sequoia",
  ...
}: let
  getName = cask: lib.lists.elemAt cask.name 0;
  getBinary = artifacts: lib.lists.elemAt artifacts.binary 0;
  getApp = artifacts: lib.lists.elemAt artifacts.app 0;

  getVariationData = cask: let
    orderedMacosVersions = [
      "sequoia"
      "sonoma"
      "ventura"
      "monterey"
      "big_sur"
    ];

    archPrefix =
      if stdenvNoCC.hostPlatform.isAarch64
      then "arm64_"
      else ""; # x86_64 is the implicit default

    variations =
      if lib.attrsets.hasAttr "variations" cask && cask.variations != null && cask.variations != {}
      then cask.variations
      else null;

    findBestVariation = osIndex:
      if variations == null || osIndex >= lib.lists.length orderedMacosVersions
      then {inherit (cask) url sha256 version artifacts;}
      else let
        osName = lib.lists.elemAt orderedMacosVersions osIndex;
        archSpecificKey = "${archPrefix}${osName}";
        osSpecificKey = osName;
      in
        if lib.attrsets.hasAttr archSpecificKey variations
        then variations."${archSpecificKey}"
        else if lib.attrsets.hasAttr osSpecificKey variations
        then variations."${osSpecificKey}"
        else findBestVariation (osIndex + 1);

    currentOsIndex = lib.lists.findFirstIndex (name: name == currentMacosName) null orderedMacosVersions;
    bestVariationAttributes = findBestVariation (
      if currentOsIndex != null
      then currentOsIndex
      else 0
    );
  in {
    url = bestVariationAttributes.url or cask.url;
    sha256 = bestVariationAttributes.sha256 or cask.sha256;
    version = bestVariationAttributes.version or cask.version;
    artifacts = bestVariationAttributes.artifacts or cask.artifacts;
  };

  caskToDerivation = cask: let
    variationData = getVariationData cask;

    inherit(variationData) url sha256 version;
    artifacts = lib.attrsets.mergeAttrsList variationData.artifacts;

    isBinary = lib.attrsets.hasAttr "binary" artifacts;
    isApp = lib.attrsets.hasAttr "app" artifacts;
    isPkg = lib.attrsets.hasAttr "pkg" artifacts;
  in
    stdenvNoCC.mkDerivation (finalAttrs: {
      pname = cask.token;
      inherit version;

      src = pkgs.fetchurl {
        inherit url;
        sha256 = lib.strings.optionalString (variationData.sha256 != "no_check") sha256;
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
          undmg $src || unzip $src || 7zz x -snld $src
        ''
        else if isBinary
        then ''
          if [ "$(file --mime-type -b "$src")" == "application/gzip" ]; then
            gunzip $src -c > ${getBinary artifacts}
          elif [ "$(file --mime-type -b "$src")" == "application/x-mach-binary" ]; then
            cp $src ${getBinary artifacts}
          fi
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

          if [ -d "Resources" ]; then
            mkdir -p $out/Resources
            cp -R Resources/* $out/Resources/
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
          cp -R ./* $out/bin/
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

  casks = lib.importJSON (brew-api + "/cask.json");
in
  lib.attrsets.listToAttrs (
    lib.lists.map (cask: {
      name = cask.token;
      value = caskToDerivation cask;
    })
    casks
  )