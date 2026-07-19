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
        ++ lib.lists.optionals usePkgPath (
          with pkgs; [
            xar
            cpio
            fd
            pbzx
          ]
        );

      unpackPhase =
        if usePkgPath
        then ''
          xar -xf $src
          for payload in */Payload; do
            case "$(file -b "$payload")" in
              *gzip*) zcat "$payload" | cpio -i ;;
              *)      pbzx -n "$payload" | cpio -i ;;
            esac
          done
        ''
        else if isApp
        then ''
          case "$src" in
            *.zip)            unzip -q "$src" ;;
            *.tar.gz|*.tgz)   tar -xzf "$src" ;;
            *.tar.xz)         tar -xJf "$src" ;;
            *.tar.bz2|*.tbz2) tar -xjf "$src" ;;
            *)
              # Dispatch by content because some cask URLs have no archive extension.
              # 7zz 26+ rejects "dangerous link via another link" patterns that are
              # legitimate in macOS .app bundles (e.g. Versions/Current chains in
              # nested frameworks). Prefer unzip for zip-format archives.
              cp -- "$src" ./archive
              mime="$(file --mime-type -b ./archive)"
              case "$mime" in
                application/zip)
                  unzip -q ./archive
                  ;;
                application/x-apple-diskimage)
                  # undmg only supports HFS images
                  if ! undmg ./archive 2>/dev/null; then
                    7zz x -snld20 ./archive
                    find . -name '*:com.apple.*' -print -delete
                  fi
                  ;;
                *)
                  # Used for APFS images
                  7zz x -snld20 ./archive
                  find . -name '*:com.apple.*' -print -delete
                  ;;
              esac
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
            *.zip)            unzip -q "$src" ;;
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
              elif [ "$mime" == "application/zip" ]; then
                unzip -q "$src"
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

          # Component pkgs unpack to a bare Contents/, the contents of a single
          # .app bundle. Wrap it back into <CFBundleName>.app and expose its
          # executable in bin/.
          if [ -f Contents/Info.plist ]; then
            plist_get() { sed -n "/<key>$1<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}" Contents/Info.plist; }
            bundle=$(plist_get CFBundleName)
            app="$out/Applications/''${bundle:-${cask.token}}.app"
            mkdir -p "$app"
            cp -R Contents "$app/"
            exe=$(plist_get CFBundleExecutable)
            if [ -n "$exe" ] && [ -f "$app/Contents/MacOS/$exe" ]; then
              makeWrapper "$app/Contents/MacOS/$exe" "$out/bin/${cask.token}"
            fi
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
