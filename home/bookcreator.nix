{ pkgs, lib, inputs, ... }: let
  # Chromium and Firefox only: WebKit fails to build in playwright-web-flake
  # 1.63.0, and the KidTron tests launch neither it nor branded Chrome.
  playwrightBrowsers = inputs.playwright-web-flake.packages.${pkgs.stdenv.hostPlatform.system}.playwright-driver.browsers.override {
    withWebkit = false;
  };
in {
  # The BookCreator repos have converged on one toolchain, so it lives here
  # rather than in a devshell per repo. Node 24, Firebase and gcloud come from
  # home.nix.
  home.packages = with pkgs; [
    # Without its own node, Yarn Classic runs under the first node on PATH.
    # The repos whose engines still say ^22 (node-api-notifications,
    # node-api-sql-analytics, rtdb-to-bq), which Yarn refuses to install under
    # Node 24, then work from `nix shell nixpkgs#nodejs_22`.
    (yarn.override { withNode = false; })
    # bookcreator-web and web-kidtron. pnpm switches itself to the version in
    # their packageManager field.
    pnpm
    # The Firebase emulators that the API repos' test runners start
    jre_headless
    # node-gyp, for native addons without a prebuild for this Node, which
    # appenginenode-download's libxmljs2 then compiles
    python3 gcc gnumake
    # psql for node-api-database's deployment/db-setup.sh, same major as the
    # Postgres image in its test/ci/postgres-compose.yaml
    postgresql_18
    docker
    (writeShellApplication {
      name = "docker-daemon";
      runtimeEnv = {
        DOCKERD_ROOTLESS = "${docker}/bin/dockerd-rootless";
        # /run/wrappers provides the newuidmap and newgidmap that rootlesskit needs
        DOCKERD_PATH = "/run/wrappers/bin:${lib.makeBinPath [ coreutils findutils gnugrep gnused ]}";
      };
      text = builtins.readFile ../scripts/docker-daemon.sh;
    })
    # node-api-comments and transcoder transcode with it, KidTron encodes its
    # recordings with it
    ffmpeg
    # automation-kidtron3030's git hooks
    lefthook
  ];

  programs.zsh.envExtra = ''
    # docker-daemon's socket
    export DOCKER_HOST="''${DOCKER_HOST:-unix://''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock}"
    # Every Playwright in the repos is 1.63.0; see the playwright-web-flake
    # input in flake.nix.
    export PLAYWRIGHT_BROWSERS_PATH=${playwrightBrowsers}
    export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
  '';
}
