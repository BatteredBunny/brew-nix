{
  pkgs,
  lib,
  brew-api,
  stdenv,
  ...
}:
let
  hasBinary = cask: lib.hasAttr "binary" (getArtifacts cask);
  hasApp = cask: lib.hasAttr "app" (getArtifacts cask);
  hasPkg = cask: lib.hasAttr "pkg" (getArtifacts cask);

  getName = cask: builtins.elemAt cask.name 0;

  getApp = cask: builtins.elemAt (getArtifacts cask).app 0;
  getPkg = cask: builtins.elemAt (getArtifacts cask).pkg 0;
  getBinary = cask: builtins.elemAt (getArtifacts cask).binary 0;
  getArtifacts = cask: lib.mergeAttrsList cask.artifacts;

  urlIsDmg = cask: lib.hasSuffix ".dmg" cask.url;
  urlIsApp = cask: lib.hasSuffix ".app" cask.url;
  urlIsPkg = cask: lib.hasSuffix ".pkg" cask.url;

  caskToDerivation =
    cask:
    stdenv.mkDerivation rec {
      pname = cask.token;
      version = cask.version;

      src = pkgs.fetchurl {
        # TODO: do we need to look at `cask.variations` and choose
        # an appropriate variation?
        url = cask.url;
        hash = lib.optionalString (cask.sha256 != "no_check") (
          builtins.convertHash {
            hash = cask.sha256;
            toHashFormat = "sri";
            hashAlgo = "sha256";
          }
        );
      };

      nativeBuildInputs =
        with pkgs;
        [
          xxd
          undmg
          unzip
          gzip
          _7zz
          makeWrapper
        ]
        ++ lib.optional (hasPkg cask) (
          with pkgs;
          [
            xar
            cpio
          ]
        );

      # unpack the downloaded source, maybe should not concern itself
      # with final artifacts just yet. Just perform bare minimum to
      # make final artifacts findable.
      # perform steps based on cask.url.
      unpackPhase =
        # uncomment for debug statements
        # ''
        #   set -x
        # '' +
        (
          if (urlIsDmg cask) then
            ''
              undmg $src
              ${
                if (hasPkg cask) then
                  ''
                    # do some more extraction on the pkg, it should probably exist at this point
                    xar -xf "${getPkg cask}"
                    for pkg in $(cat Distribution | grep -oE "#.+\.pkg" | sed -e "s/^#//" -e "s/$/\/Payload/"); do
                      zcat $pkg | cpio -i
                    done
                  ''
                else
                  ''''
              }
              ${
                if (hasApp cask) then
                  ''
                    echo "checking app exists..."

                    if [ ! -e "${getApp cask}" ]; then
                      echo "NO SUCH FILE: ${getApp cask}"
                      ls -la
                      exit 1
                    fi
                  ''
                else
                  ''''
              }
            ''
          else if (urlIsPkg cask) then
            ''
              xar -xf $src
              for pkg in $(cat Distribution | grep -oE "#.+\.pkg" | sed -e "s/^#//" -e "s/$/\/Payload/"); do
                zcat $pkg | cpio -i
              done
            ''
          else if (urlIsApp cask) then
            ''
              7zz x -snld $src
            ''
          # we don't know a-priori what `src` is...
          else
            ''
              SRC_FILE_TYPE=$(file --mime-type -b "$src")

              # https://newosxbook.com/DMG.html
              # DMG files are proprietary format. We can detect this way.
              if [ -n "$(xxd -s -512 -l 4 "$src" | grep "koly$")" ]; then
                undmg $src
              ${
                if (hasBinary cask) then
                  # TODO: I am not sure this is correct...
                  # we should probably just blindly unpack into $out
                  # and not base it upon the artifacts
                  ''
                    elif [ "$SRC_FILE_TYPE" == "application/gzip" ]; then
                      gunzip $src -c > ${getBinary cask}
                    elif [ "$SRC_FILE_TYPE" == "application/x-mach-binary" ]; then
                      cp $src ${getBinary cask}
                  ''
                else
                  ''''
              }
              elif [ "$SRC_FILE_TYPE" == "application/zip" ]; then
                unzip $src
              else
                echo "Unhandled file type: $SRC_FILE_TYPE"
                exit 1
              fi
            ''
        );

      # TODO: WHY ARE WE IN A SUBDIR NOW?
      # I cannot figure out why the `cd` command happens ...
      # It is helpful, but I just don't know how it works.

      sourceRoot = lib.optionalString (hasApp cask) (getApp cask);

      # apply final installations on all artifacts
      installPhase = ''
        pwd
        ls -la
        ${
          if (hasPkg cask) then
            ''
              if [ -d "Applications" ]; then
                mkdir -p $out/Applications
                cp -R Applications/* "$out/Applications/"
              fi

              if [ -d "Resources" ]; then
                mkdir -p "$out/Resources"
                cp -R Resources/* "$out/Resources/"
              fi

              if [ -d "Library" ]; then
                mkdir -p "$out/Library"
                cp -R Library/* "$out/Library/"
              fi
            ''
          else
            ''''
        }
        ${
          if (hasApp cask) then
            ''
              mkdir -p "$out/Applications/${sourceRoot}"
              cp -R . "$out/Applications/${sourceRoot}"

              if [[ -e "$out/Applications/${sourceRoot}/Contents/MacOS/${getName cask}" ]]; then
                makeWrapper "$out/Applications/${sourceRoot}/Contents/MacOS/${getName cask}" $out/bin/${cask.token}
              elif [[ -e "$out/Applications/${sourceRoot}/Contents/MacOS/${lib.removeSuffix ".app" sourceRoot}" ]]; then
                makeWrapper "$out/Applications/${sourceRoot}/Contents/MacOS/${lib.removeSuffix ".app" sourceRoot}" $out/bin/${cask.token}
              fi
            ''
          else
            ''''
        }
        ${
          if (hasBinary cask && !hasApp cask) then
            ''
              mkdir -p $out/bin
              cp -R "./*" "$out/bin"
            ''
          else
            ''''
        }
      '';

      meta = {
        homepage = cask.homepage;
        description = cask.desc;
        platforms = lib.platforms.darwin;
        mainProgram = if (hasBinary cask && !hasApp cask) then (getBinary cask) else (cask.token);
      };
    };

  casks = builtins.fromJSON (builtins.readFile (brew-api + "/cask.json"));
in
builtins.listToAttrs (
  builtins.map (cask: {
    name = cask.token;
    value = caskToDerivation cask;
  }) casks
)
