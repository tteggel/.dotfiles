{
  description = "Zellij (from fork with pane shader support) + dim-unfocused plugin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zellij-src = {
      url = "github:tteggel/zellij/pane-shaders-static";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    zellij-src,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [(import rust-overlay)];
    };
    rustToolchain = pkgs.rust-bin.stable.latest.default.override {
      targets = ["wasm32-wasip1" "wasm32-unknown-unknown"];
    };
    pluginCargoVendored = pkgs.rustPlatform.importCargoLock {
      lockFile = ./Cargo.lock;
    };
    zellijCargoVendored = pkgs.rustPlatform.importCargoLock {
      lockFile = zellij-src + "/Cargo.lock";
    };
    shaderWasm = pkgs.stdenv.mkDerivation {
      pname = "dim-shader";
      version = "0.1.0";
      src = ./shader;
      nativeBuildInputs = [rustToolchain];
      buildPhase = ''
        export HOME=$TMPDIR
        mkdir -p .cargo
        cat > .cargo/config.toml <<'TOML'
        [source.crates-io]
        replace-with = "vendored-sources"

        [source.vendored-sources]
        directory = "vendor"
        TOML

        cargo build --target wasm32-unknown-unknown --release --offline 2>/dev/null || \
        cargo build --target wasm32-unknown-unknown --release
      '';
      installPhase = ''
        mkdir -p $out
        cp target/wasm32-unknown-unknown/release/dim_shader.wasm $out/
      '';
    };
  in {
    packages.${system} = rec {
      zellij = pkgs.zellij.overrideAttrs (old: {
        version = "0.44.0-unstable";
        src = zellij-src;
        cargoDeps = zellijCargoVendored;
        postPatch = ''
          substituteInPlace Cargo.toml \
            --replace-fail ', "vendored_curl"' "" || true
        '';
        doInstallCheck = false;
      });

      dim-unfocused = pkgs.stdenv.mkDerivation {
        pname = "dim-unfocused";
        version = "0.1.0";
        src = builtins.path {
          path = ./.;
          filter = path: type:
            let name = builtins.baseNameOf path;
            in name != "flake.nix" && name != "flake.lock" && name != "target" && name != "zellij-src" && name != "result" && name != "shader";
        };

        nativeBuildInputs = [rustToolchain];

        buildPhase = ''
          export HOME=$TMPDIR
          ln -s ${zellij-src} zellij-src
          ln -s ${pluginCargoVendored} vendor
          mkdir -p .cargo
          cat > .cargo/config.toml <<'TOML'
          [source.crates-io]
          replace-with = "vendored-sources"

          [source.vendored-sources]
          directory = "vendor"
          TOML

          export SHADER_WASM_PATH="${shaderWasm}/dim_shader.wasm"
          cargo build --target wasm32-wasip1 --release --offline
        '';

        installPhase = ''
          mkdir -p $out/share/zellij/plugins
          cp target/wasm32-wasip1/release/dim-unfocused.wasm $out/share/zellij/plugins/
        '';
      };
      default = dim-unfocused;
    };

    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [rustToolchain];
    };
  };
}
