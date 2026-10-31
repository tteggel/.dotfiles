# Entire CLI plugins from upstream's prebuilt releases; llm-agents only
# packages the CLI itself. Plugins need no registration: `entire <name>` runs
# `entire-<name>` from PATH.
#
# Versions and hashes live in entire-plugins.json rather than in flake inputs,
# because the release asset names embed the version. scripts/update-system.sh
# bumps every plugin there to its latest release; to add one, add its name
# (the part after `entire-`) to the JSON and run that script.
{ pkgs, lib }: let
  plugin = name: pin: pkgs.stdenvNoCC.mkDerivation {
    pname = "entire-${name}";
    inherit (pin) version;
    src = pkgs.fetchurl {
      url = "https://github.com/entireio/entire-${name}/releases/download/v${pin.version}/entire-${name}_${pin.version}_linux_amd64.tar.gz";
      inherit (pin) hash;
    };
    # Some tarballs hold bare files, others wrap them in a ./ directory.
    sourceRoot = ".";
    nativeBuildInputs = [ pkgs.patchelf ];
    dontBuild = true;
    # Upstream releases are already stripped.
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 entire-${name} "$out/bin/entire-${name}"
      runHook postInstall
    '';
    # entire-graph links libstdc++; the rest are static. Not autoPatchelfHook:
    # it sets the interpreter before the rpath, and that order leaves
    # entire-graph segfaulting at startup. The reverse order works.
    postFixup = ''
      bin="$out/bin/entire-${name}"
      if patchelf --print-interpreter "$bin" >/dev/null 2>&1; then
        patchelf --set-rpath ${lib.makeLibraryPath [ pkgs.stdenv.cc.libc pkgs.stdenv.cc.cc.lib ]} "$bin"
        patchelf --set-interpreter ${pkgs.stdenv.cc.bintools.dynamicLinker} "$bin"
      fi
    '';
    meta = {
      homepage = "https://github.com/entireio/entire-${name}";
      mainProgram = "entire-${name}";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };
in pkgs.symlinkJoin {
  name = "entire-plugins";
  paths = lib.mapAttrsToList plugin (lib.importJSON ./entire-plugins.json);
}
