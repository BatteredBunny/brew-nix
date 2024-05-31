# brew-nix

Experimental nix expression to package all MacOS casks from [homebrew](https://brew.sh/) automatically. 

## Benefits over nix-darwin's homebrew module
1. No homebrew needed, packages are fully managed by nix.
2. Fully nix package expressions, everything is type checked and it will give you an error when you specify an invalid package for example.

## Dependencies
It relies on nix 2.19 due to using ``builtins.convertHash``. So make sure you have that or newer.
As of writing this on 2024-05-04, nixos-unstable seems to come with nix 2.18.2

## Limitations
1. Running most programs with ``nix run`` wont work, so you should install them first.
2. Some programs refuse to run from non standard locations, since this is automatic there isnt a good way to fix it.
3. About 700 casks dont come with hashes, so you have to override the package and provide the hash yourself.

## Basic usage
```bash
nix build github:BatteredBunny/brew-nix#blender
./result/Applications/Blender.app/Contents/MacOS/Blender
```

## Using with home-manager
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
  nixVersions.latest # if your nix version is under 2.19
  brewCasks.marta
];
```
