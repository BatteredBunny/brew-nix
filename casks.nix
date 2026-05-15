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

  # The url key is usually the binary for arm64, for intel we need to select the url from variants
  intelMacosPreference = [
    "tahoe"
    "sequoia"
    "sonoma"
    "ventura"
    "monterey"
    "big_sur"
    "catalina"
  ];

  defaultVariationFor =
    if pkgs.stdenv.hostPlatform.isx86_64
    then cask:
      if cask ? variations
      then lib.lists.findFirst (name: cask.variations ? ${name}) null intelMacosPreference
      else null
    else _: null;

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

    # Prefer .app to .pkg when both are included in the dmg since using .app doesn't break the code signature
    usePkgPath = isPkg && !(isApp && url != null && lib.strings.hasSuffix ".dmg" url);
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
        ++ lib.lists.optional usePkgPath (
          with pkgs; [
            xar
            cpio
            fd
          ]
        );

      unpackPhase =
        if usePkgPath
        then ''
          xar -xf $src
          for pkg in $(cat Distribution | grep -oE "#.+\.pkg" | sed -e "s/^#//" -e "s/$/\/Payload/"); do
            zcat $pkg | cpio -i
          done
        ''
        else if isApp
        then ''
          case "$src" in
            *.zip)            unzip "$src" ;;
            *.tar.gz|*.tgz)   tar -xzf "$src" ;;
            *.tar.xz)         tar -xJf "$src" ;;
            *.tar.bz2|*.tbz2) tar -xjf "$src" ;;
            *)
              # Try undmg first, then 7zz if it doesn't work
              # 7zz has weird issues with decompressing many times but supports more formats
              cp -- "$src" ./archive
              if ! undmg ./archive 2>/dev/null; then
                7zz x -snld ./archive
                find . -name '*:com.apple.*' -print -delete
              fi
              rm -f ./archive
              if [ ! -e "${getApp artifacts}" ]; then
                nested=$(find . -mindepth 2 -maxdepth 3 -name "${getApp artifacts}" -print -quit)
                [ -n "$nested" ] && mv "$nested" .
              fi
              # Often comes with symlink to /Applications which we dont want
              find . -maxdepth 1 -type l -delete
              ;;
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

      sourceRoot = lib.strings.optionalString (isApp && !usePkgPath) (getApp artifacts);

      # Patching the artifacts invalidates code signing
      dontPatchShebangs = true;
      dontUpdateAutotoolsGnuConfigScripts = true;
      dontStrip = true;
      dontPruneLibtoolFiles = true;

      installPhase =
        if usePkgPath
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
          app_dir="$out/Applications/${finalAttrs.sourceRoot}"
          mkdir -p "$app_dir"
          cp -R . "$app_dir"

          macos="$app_dir/Contents/MacOS"
          exe=""
          if [ -e "$macos/${getName cask}" ]; then
            exe="${getName cask}"
          elif [ -e "$macos/${lib.strings.removeSuffix ".app" finalAttrs.sourceRoot}" ]; then
            exe="${lib.strings.removeSuffix ".app" finalAttrs.sourceRoot}"
          elif [ -f "$app_dir/Contents/Info.plist" ]; then
            exe=$(sed -n '/<key>CFBundleExecutable<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$app_dir/Contents/Info.plist")
          fi
          if [ -n "$exe" ] && [ -e "$macos/$exe" ]; then
            makeWrapper "$macos/$exe" "$out/bin/${cask.token}"
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
          then baseNameOf (getBinary artifacts)
          else cask.token;
      };
    });

  casks = lib.trivial.importJSON (brew-api + "/cask.json");
in
  lib.attrsets.listToAttrs (
    lib.lists.map (cask: {
      name = cask.token;
      value = lib.customisation.makeOverridable (caskToDerivation cask) {
        variation = defaultVariationFor cask;
      };
    })
    casks
  )