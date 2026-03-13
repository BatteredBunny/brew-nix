# brew-nix

An experimental nix expression as a nixpkgs overlay to package all macOS [Homebrew Casks](https://brew.sh/) automatically.

## Benefits over nix-darwin's homebrew module

1. No homebrew installation needed; packages are fully managed by nix.
2. Pure nix, package derivations; everything is type checked and it will give you an error when you specify an invalid package for example.

## Limitations/Flaws

1. Running most programs with `nix run` won't work, you'll have to build them first.
2. Some programs refuse to run from non-standard locations, since this is automatic there isn't a good way to fix it.
3. There're about 700 casks without hashes, so you have to [override the derivation attributes & provide a hash explicitly](#overriding-casks-derivation-attributes-for-casks-with-no-hash).
4. Having several generations with this will take A LOT of disk space, so keep that in mind.

## Related projects

- [mac-app-util](https://github.com/hraban/mac-app-util)
- [nixcasks](https://github.com/jcszymansk/nixcasks)

# Usage examples

## Basic usage

```bash
nix build github:BatteredBunny/brew-nix#blender
./result/Applications/Blender.app/Contents/MacOS/Blender
```

or declaratively

```nix
home.packages = [ pkgs.brewCasks.visual-studio-code ];
```

## Overriding cask's derivation attributes for casks with no hash

Many casks do not come with their hash so you'll have to provide one explicitly.

```nix
home.packages = with pkgs; [
  (brewCasks.marta.overrideAttrs (oldAttrs: {
    src = pkgs.fetchurl {
      url = builtins.head oldAttrs.src.urls;
      hash = lib.fakeHash; # Replace with actual hash after building once
    };
  }))
];
```

## Overriding cask's variation

Explicitly choose homebrew cask variations (Quite a few casks have variations for different architectures or macOS versions).
You can look up each cask's respective variations at [brew.sh](https://brew.sh/).

```nix
home.packages = lib.attrsets.attrValues {
  vscode = (pkgs.brewCasks.visual-studio-code.override {variation = "sequoia";});
};
```

## Overriding both cask's variation & derivation attributes

```nix
home.packages = lib.attrsets.attrValues {
  vscode = (pkgs.brewCasks.visual-studio-code.override {variation = "sequoia";}).overrideAttrs (oldAttrs: {
    src = pkgs.fetchurl {
      url = lib.lists.head oldAttrs.src.urls;
      hash = lib.fakeHash; # Replace with actual hash after building once
    };
  });
};
```

# Setup

`brew-nix` is structured into 2 repos for modularity:
- The main repo `brew-nix` containg the nix expression to parse cask data to nix packages.
- Automated [`brew-api`](https://github.com/BatteredBunny/brew-api) repo containing the brew casks summary information.

This has the benefit of being able to keep the git history of `brew-nix` clean, and giving the user the freedom to easily override the data used to generate the nix expressions and or update `brew-api` seperatly from `brew-nix` if needed.

> [!WARNING]
> `brew-api` input part is not optional. You should define your own `brew-api` input like below.
>
> If you omit it, `brew-nix` will use a stale version of `brew-api` which is updated infrequently and may not work.

## Setup with nix-darwin

See [`examples/flake.nix`](examples/flake.nix).

## Setup with home-manager

```nix
# flake.nix
inputs = {
  brew-nix = {
    url = "github:BatteredBunny/brew-nix";
    inputs.brew-api.follows = "brew-api";
  };
  brew-api = {
    url = "github:BatteredBunny/brew-api";
    flake = false;
  };
};
```

```nix
# home.nix
nixpkgs = {
  overlays = [
    inputs.brew-nix.overlays.default
  ];
};

home.packages = with pkgs; [
  brewCasks.marta
  brewCasks."firefox@developer-edition" # Casks with special characters in their name need to be defined in quotes
];
```
