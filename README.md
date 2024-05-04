# brew.nix

Experimental nix expression to package all MacOS casks from [homebrew](https://brew.sh/).

## Dependencies
It relies on nix 2.19 due to using ``builtins.convertHash``. So make sure you have that or newer.
As of writing this on 2024-05-04, nixos-unstable seems to come with nix 2.18.2

## Broken
1. Running it without cloning the repo, since the expression depends on the api json response and its hash is always changing the hash in flake.lock has to be updated as well
3. Running most programs with nix run

## Usage
```
git clone https://github.com/BatteredBunny/brew.nix
cd brew.nix
nix flake update cask
nix build .#blender
```