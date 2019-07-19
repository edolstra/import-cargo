{
  name = "import-cargo";

  epoch = 201906;

  description = "A function for fetching the crates listed in a Cargo lock file";

  outputs = inputs: rec {

    builders.importCargo =
      { lockFile, pkgs }:
      let lockFile' = builtins.fromTOML (builtins.readFile lockFile); in
      rec {

        # Fetch and unpack the crates specified in the lock file.
        unpackedCrates = map
          (pkg:

            let
              isGit = builtins.match ''git\+(.*)\?rev=([0-9a-f]+)(#.*)?'' pkg.source;
              registry = "registry+https://github.com/rust-lang/crates.io-index";
            in

            if pkg.source == registry then
              let
                sha256 = lockFile'.metadata."checksum ${pkg.name} ${pkg.version} (${registry})";
                tarball = import <nix/fetchurl.nix> {
                  url = "https://crates.io/api/v1/crates/${pkg.name}/${pkg.version}/download";
                  inherit sha256;
                };
              in pkgs.runCommand "${pkg.name}-${pkg.version}" {}
                ''
                  mkdir $out

                  tar xvf ${tarball} -C $out --strip-components=1

                  # Add just enough metadata to keep Cargo happy.
                  printf '{"files":{},"package":"${sha256}"}' > "$out/.cargo-checksum.json"
                ''

            else if isGit != null then
              let
                rev = builtins.elemAt isGit 1;
                url = builtins.elemAt isGit 0;
                tree = builtins.fetchGit { inherit url rev; };
              in pkgs.runCommand "${pkg.name}-${pkg.version}" {}
                ''
                  tree=${tree}

                  if grep --quiet '\[workspace\]' $tree/Cargo.toml; then
                    if [[ -e $tree/${pkg.name} ]]; then
                      tree=$tree/${pkg.name}
                    fi
                  fi

                  cp -prvd $tree/ $out
                  chmod u+w $out

                  # Add just enough metadata to keep Cargo happy.
                  printf '{"files":{},"package":null}' > "$out/.cargo-checksum.json"

                  cat > $out/.cargo-config <<EOF
                  [source."${url}"]
                  git = "${url}"
                  rev = "${rev}"
                  replace-with = "vendored-sources"
                  EOF
                ''

            else throw "Unsupported crate source '${pkg.source}' in dependency '${pkg.name}-${pkg.version}'.")

          (builtins.filter (pkg: pkg.source or "" != "") lockFile'.package);

        # Create a directory that symlinks all the crate sources and
        # contains a cargo configuration file that redirects to those
        # sources.
        vendorDir = pkgs.runCommand "cargo-vendor-dir" {}
          ''
            mkdir -p $out/vendor

            cat > $out/vendor/config <<EOF
            [source.crates-io]
            replace-with = "vendored-sources"

            [source.vendored-sources]
            directory = "vendor"
            EOF

            for i in ${toString unpackedCrates}; do
              ln -s $i $out/vendor/$(basename "$i" | cut -c 34-)
              if [[ -e "$i/.cargo-config" ]]; then
                cat "$i/.cargo-config" >> $out/vendor/config
              fi
            done
          '';

        # Create a setup hook that will initialize CARGO_HOME. Note:
        # we don't point CARGO_HOME at the vendor tree directly
        # because then we end up with a runtime dependency on it.
        cargoHome = pkgs.makeSetupHook {}
          (pkgs.writeScript "make-cargo-home" ''
            if [[ -z $CARGO_HOME ]]; then
              export CARGO_HOME=$TMPDIR/vendor
              ln -s ${vendorDir}/vendor $CARGO_HOME
            fi
          '');
      };

  };

}
