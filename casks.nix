{
  pkgs,
  lib ? pkgs.lib,
  brew-api,
  stdenv ? pkgs.stdenv,
  currentMacosName ? "sequoia",
  ...
}: let
  getName = cask: builtins.elemAt cask.name 0;
  getBinary = artifacts: builtins.elemAt artifacts.binary 0;
  getApp = artifacts: builtins.elemAt artifacts.app 0;

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
      else ""; # x86_64 is the implicit default

    variations =
      if lib.hasAttr "variations" cask && cask.variations != null && cask.variations != {}
      then cask.variations
      else null;

    findBestVariation = osIndex:
      if variations == null || osIndex >= builtins.length orderedMacosVersions
      then {}
      else let
        osName = builtins.elemAt orderedMacosVersions osIndex;
        archSpecificKey = "${archPrefix}${osName}";
        osSpecificKey = osName;
      in
        if lib.hasAttr archSpecificKey variations
        then variations."${archSpecificKey}"
        else if lib.hasAttr osSpecificKey variations
        then variations."${osSpecificKey}"
        else findBestVariation (osIndex + 1);

    currentOsIndex = lib.lists.findFirstIndex (name: name == currentMacosName) null orderedMacosVersions;

    bestVariationAttributes = findBestVariation (
      if currentOsIndex != null
      then currentOsIndex
      else 0
    );
  in
    builtins.recursiveAttrsMerge bestVariationAttributes {
      inherit (cask) url sha256 version;
      artifacts = lib.mergeAttrsList (bestVariationAttributes.artifacts or cask.artifacts);
    };

  caskToDerivation = cask: let
    variationData = getVariationData cask;

    artifacts = lib.mergeAttrsList variationData.artifacts;

    isBinary = lib.hasAttr "binary" artifacts;
    isApp = lib.hasAttr "app" artifacts;
    isPkg = lib.hasAttr "pkg" artifacts;
  in
    stdenv.mkDerivation (finalAttrs: {
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
        ++ lib.optional isPkg (
          with pkgs; [
            xar
            cpio
          ]
        );

      # Unpack phase remains largely the same, but uses the flags based on variation artifacts
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
          undmg $src || 7zz x -snld $src
        ''
        else if isBinary
        then ''
          # Use artifacts from variationData to get the binary name
          local binaryName="${getBinary artifacts}"
          if [ "$(file --mime-type -b "$src")" == "application/gzip" ]; then
            gunzip $src -c > "$binaryName"
          elif [ "$(file --mime-type -b "$src")" == "application/x-mach-binary" ]; then
            cp $src "$binaryName"
          else
            echo "Unknown binary type for $src"
            exit 1
          fi
        ''
        else ""; # Handle cases with no common artifacts

      # Source root uses app name from variation data
      sourceRoot = lib.optionalString isApp (getApp artifacts);

      # Patching shebangs invalidates code signing
      dontPatchShebangs = true;

      # Install phase remains largely the same, using flags and names from variation artifacts
      installPhase =
        if isPkg
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
        else if isApp
        then ''
          mkdir -p "$out/Applications/${finalAttrs.sourceRoot}"
          cp -R . "$out/Applications/${finalAttrs.sourceRoot}"

          # Try both common naming conventions for the executable within the app bundle
          local appBundlePath="$out/Applications/${finalAttrs.sourceRoot}/Contents/MacOS"
          local mainExecutable=""

          if [[ -e "$appBundlePath/${getName cask}" ]]; then
            mainExecutable="$appBundlePath/${getName cask}"
          elif [[ -e "$appBundlePath/${lib.removeSuffix ".app" finalAttrs.sourceRoot}" ]]; then
            mainExecutable="$appBundlePath/${lib.removeSuffix ".app" finalAttrs.sourceRoot}"
          fi

          if [[ -n "$mainExecutable" ]]; then
            makeWrapper "$mainExecutable" $out/bin/${cask.token}
          else
            echo "Warning: Could not find main executable for ${cask.token} app at $appBundlePath" >&2
            # Still create the wrapper just in case, it might work if the app is run differently
            # or the executable path is determined dynamically by the app bundle itself.
            makeWrapper "$appBundlePath/${getName cask}" $out/bin/${cask.token} || true
          fi
        ''
        else if (isBinary && !isApp)
        then
          # For simple binaries, copy the binary to $out/bin
          ''
            mkdir -p $out/bin
            # Use artifacts from variationData to get the binary name
            cp "${getBinary artifacts}" $out/bin/
          ''
        else ""; # No install phase needed for unknown/unhandled types

      meta = {
        inherit (cask) homepage; # Homepage is usually not varied
        description = cask.desc; # Description is usually not varied
        platforms = lib.platforms.darwin;
        # Main program depends on the selected artifact type from variation data
        mainProgram =
          if (isBinary && !isApp)
          then (getBinary artifacts)
          else cask.token;
      };
    });

  casks = lib.importJSON (brew-api + "/cask.json");

  # Filter out casks that don't seem to have standard artifact types we handle
  # (binary, app, pkg) to avoid build failures for weird casks.
  # Merge artifacts first to check if any standard types exist.
  # You might want to adjust or remove this filter depending on how comprehensive
  # you want this to be.
  filteredCasks =
    builtins.filter (
      cask: let
        variationData = getVariationData cask;
        artifacts = lib.mergeAttrsList variationData.artifacts;
      in
        lib.hasAttr "binary" artifacts
        || lib.hasAttr "app" artifacts
        || lib.hasAttr "pkg" artifacts
    )
    casks;
in
  # Convert the list of filtered casks into an attribute set of derivations
  lib.listToAttrs (
    builtins.map (cask: {
      name = cask.token;
      value = caskToDerivation cask;
    })
    filteredCasks
  )