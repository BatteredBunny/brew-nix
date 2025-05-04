{
  pkgs,
  lib,
  brew-api,
  stdenv,
  currentMacosName ? "sequoia",
  ...
}: let
  getName = cask: builtins.elemAt cask.name 0;
  getArtifacts = cask: lib.mergeAttrsList cask.artifacts;
  getBinary = cask: builtins.elemAt (getArtifacts cask).binary 0;
  getApp = cask: builtins.elemAt (getArtifacts cask).app 0;

  hasBinary = cask: lib.hasAttr "binary" (getArtifacts cask);
  hasApp = cask: lib.hasAttr "app" (getArtifacts cask);
  hasPkg = cask: lib.hasAttr "pkg" (getArtifacts cask);

  getVariationData = cask: let
    orderedMacosVersions = [
      "sequoia"
      "sonoma"
      "ventura"
      "monterey"
      "big_sur"
    ];

    archPrefix =
      if stdenv.hostPlatform.isAarch64
      then "arm64_"
      else "";

    variations =
      if lib.hasAttr "variations" cask && cask.variations != null && cask.variations != {}
      then cask.variations
      else null;

    # Recursive function to find the best matching variation
    findBestVariation = osIndex:
      if variations == null || osIndex >= builtins.length orderedMacosVersions
      then
        # Base case: No variations or reached end of list, return default attributes
        {inherit (cask) url sha256 version artifacts;}
      else let
        osName = builtins.elemAt orderedMacosVersions osIndex;
        archSpecificKey = "${archPrefix}${osName}";
        osSpecificKey = osName;
      in
        # Check arch-specific key first
        if lib.hasAttr archSpecificKey variations
        then variations."${archSpecificKey}"
        # Then check OS-specific key (often x86_64)
        else if lib.hasAttr osSpecificKey variations
        then variations."${osSpecificKey}"
        # Otherwise, recurse to the next older version
        else findBestVariation (osIndex + 1);

    # Find the starting index in the ordered list for the current OS
    currentOsIndex = lib.lists.findFirstIndex (name: name == currentMacosName) null orderedMacosVersions;

    # Start the search from the current OS index (or 0 if current OS not found/mapped)
    bestVariationData = findBestVariation (
      if currentOsIndex != null
      then currentOsIndex
      else 0
    );
  in {
    url = bestVariationData.url or cask.url;
    sha256 = bestVariationData.sha256 or cask.sha256;
    version = bestVariationData.version or cask.version;
    artifacts = bestVariationData.artifacts or cask.artifacts;
  };

  caskToDerivation = cask: let
    variationData = getVariationData cask;
  in
    stdenv.mkDerivation rec {
      pname = cask.token;
      version = variationData.version;

      src = pkgs.fetchurl {
        url = variationData.url;
        sha256 = lib.optionalString (variationData.sha256 != "no_check") variationData.sha256;
      };

      nativeBuildInputs = with pkgs;
        [
          undmg
          unzip
          gzip
          _7zz
          makeWrapper
        ]
        ++ lib.optional (hasPkg cask) (with pkgs; [
          xar
          cpio
        ]);

      unpackPhase =
        if (hasPkg cask)
        then ''
          xar -xf $src
          for pkg in $(cat Distribution | grep -oE "#.+\.pkg" | sed -e "s/^#//" -e "s/$/\/Payload/"); do
            zcat $pkg | cpio -i
          done
        ''
        else if (hasApp cask)
        then ''
          undmg $src || 7zz x -snld $src
        ''
        else if (hasBinary cask)
        then ''
          if [ "$(file --mime-type -b "$src")" == "application/gzip" ]; then
            gunzip $src -c > ${getBinary cask}
          elif [ "$(file --mime-type -b "$src")" == "application/x-mach-binary" ]; then
            cp $src ${getBinary cask}
          fi
        ''
        else "";

      sourceRoot = lib.optionalString (hasApp cask) (getApp cask);

      # Patching shebangs invalidates code signing
      dontPatchShebangs = true;

      installPhase =
        if (hasPkg cask)
        then ''
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
        else if (hasApp cask)
        then ''
          mkdir -p "$out/Applications/${sourceRoot}"
          cp -R . "$out/Applications/${sourceRoot}"

          if [[ -e "$out/Applications/${sourceRoot}/Contents/MacOS/${getName cask}" ]]; then
            makeWrapper "$out/Applications/${sourceRoot}/Contents/MacOS/${getName cask}" $out/bin/${cask.token}
          elif [[ -e "$out/Applications/${sourceRoot}/Contents/MacOS/${lib.removeSuffix ".app" sourceRoot}" ]]; then
            makeWrapper "$out/Applications/${sourceRoot}/Contents/MacOS/${lib.removeSuffix ".app" sourceRoot}" $out/bin/${cask.token}
          fi
        ''
        else if (hasBinary cask && !hasApp cask)
        then ''
          mkdir -p $out/bin
          cp -R ./* $out/bin
        ''
        else "";

      meta = {
        homepage = cask.homepage;
        description = cask.desc;
        platforms = lib.platforms.darwin;
        mainProgram =
          if (hasBinary cask && !hasApp cask)
          then (getBinary cask)
          else (cask.token);
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
