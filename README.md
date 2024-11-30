# brew-nix

Experimental nix expression to package all MacOS casks from [homebrew](https://brew.sh/) automatically.

## Dependencies
Requires at least nixos 24.11 or nixos-unstable to work due to relying on ``builtins.convertHash`` from nix 2.19

## Benefits over nix-darwin's homebrew module
1. No homebrew needed, packages are fully managed by nix.
2. Fully nix package expressions, everything is type checked and it will give you an error when you specify an invalid package for example.

## Limitations/flaws
1. Running most programs with ``nix run`` wont work, so you should install them first.
2. Some programs refuse to run from non standard locations, since this is automatic there isnt a good way to fix it.
3. About 700 casks dont come with hashes, so you have to override the package and provide the hash yourself.
4. Having multiple generations of this will take A LOT of space, so keep that in mind

## Related projects
- [mac-app-util](https://github.com/hraban/mac-app-util)
- [nixcasks](https://github.com/jcszymansk/nixcasks)

## Basic usage
```bash
nix build github:BatteredBunny/brew-nix#blender
./result/Applications/Blender.app/Contents/MacOS/Blender
```

## Overriding casks with no hash
Many casks come with no hash so you have to provide on yourself
```nix
home.packages = with pkgs; [
  (brewCasks.marta.overrideAttrs (o: {
    src = pkgs.fetchurl {
      url = builtins.head oldAttrs.src.urls;
      hash = lib.fakeHash; # Replace me with real hash after building once
    };
  }))
];
```

# Usage examples

## Using with nix-darwin

See [`examples/flake.nix`](examples/flake.nix).

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
  brewCasks.marta
  brewCasks."firefox@developer-edition" # Casks with special characters in their name need to be defined in quotes
];
```
