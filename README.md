# brew.nix

Experimental nix expression to package all MacOS casks from [homebrew](https://brew.sh/).

## Dependencies
It relies on nix 2.19 due to using ``builtins.convertHash``. So make sure you have that or newer.
As of writing this on 2024-05-04, nixos-unstable seems to come with nix 2.18.2

## Broken
1. Running it without cloning the repo, since the expression depends on the api json response and its hash is always changing the hash in flake.lock has to be updated as well
2. Running most programs with ``nix run``, they should work when you install them though.

## Basic usage
```
git clone https://github.com/BatteredBunny/brew.nix
cd brew.nix
nix flake update brew-cask
nix build .#blender
./result/Applications/Blender.app/Contents/MacOS/Blender
```

## Using with home-manager
```
# flake.nix
inputs = {
  brew-nix.url = "github:BatteredBunny/brew.nix";
};
```
```
# home.nix
nixpkgs = {
  overlays = [
    inputs.brew-nix.overlay.${builtins.currentSystem}
  ];
};

home.packages = with pkgs; [
  nixVersions.latest # if your nix version is under 2.19
  brewCasks.marta 
];
```
