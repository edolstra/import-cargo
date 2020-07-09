# `import-cargo`

Simple [flake](https://www.tweag.io/blog/2020-05-25-flakes/) to import all dependencies from
a [`Cargo.lock`](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html)
as [fixed-output derivation](https://nixos.org/nix/manual/#fixed-output-drvs) using the
checksum and URL from the lockfile.

## Usage

This example demonstrates how to build a local Cargo project with a
`flake.nix`:

``` nix
{
  description = "My Rust project";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-20.03;
    import-cargo.url = github:edolstra/import-cargo;
  };

  outputs = { self, nixpkgs, import-cargo }: let

    inherit (import-cargo.builders) importCargo;

  in {

    defaultPackage.x86_64-linux =
      with import nixpkgs { system = "x86_64-linux"; };
      stdenv.mkDerivation {
        name = "testrust";
        src = self;

        nativeBuildInputs = [
          # setupHook which makes sure that a CARGO_HOME with vendored dependencies
          # exists
          (importCargo { lockFile = ./Cargo.lock; inherit pkgs; }).cargoHome

          # Build-time dependencies
          rustc cargo
        ];

        buildPhase = ''
          cargo build --release --offline
        '';

        installPhase = ''
          install -Dm775 ./target/release/testrust $out/bin/testrust
        '';

      };

  };
}
```
