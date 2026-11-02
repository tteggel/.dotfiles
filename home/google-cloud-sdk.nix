{ pkgs }: let
  sdk = pkgs.google-cloud-sdk.withExtraComponents [
    pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
  ];
in sdk.overrideAttrs (old: {
  # withExtraComponents joins core, alpha and beta into one SDK. Remove PAM
  # from that final command surface, so global flags, absolute paths and
  # direct invocation of lib/gcloud.py cannot sidestep a shell permission rule.
  # This changes the installed SDK; it does not revoke Google Cloud access.
  # symlinkJoin embeds postBuild in buildCommand; overriding postBuild itself
  # would leave the already-generated builder unchanged.
  buildCommand = old.buildCommand + ''
    test -d "$out/google-cloud-sdk/lib/surface/pam"
    rm -rf "$out/google-cloud-sdk/lib/surface/pam" \
           "$out/google-cloud-sdk/lib/surface/alpha/pam" \
           "$out/google-cloud-sdk/lib/surface/beta/pam"

    # The browser logins (`gcloud auth login`, `gcloud auth application-default
    # login`) listen on 127.0.0.1:8085 and redirect to http://localhost:8085/.
    # For the host "localhost", the vendored google-auth-oauthlib (SDK >= 591)
    # also reserves ::1:8085 with bind() and no listen(), so a browser that
    # tries ::1 first is refused and falls back. Consomme mirrors that bind()
    # as a Windows listener that accepts and never forwards
    # (microsoft/WSL#41860), so Windows Chrome hangs on ::1. The loopback
    # literal skips both the reservation and ::1. Google accepts it for both
    # gcloud clients. Replace the symlink with a patched copy and drop its
    # cached bytecode.
    creds="$out/google-cloud-sdk/lib/googlecloudsdk/core/credentials"
    flow_src=$(readlink -f "$creds/flow.py")
    rm "$creds/flow.py"
    rm -f "$creds"/__pycache__/flow.*.pyc
    substitute "$flow_src" "$creds/flow.py" \
      --replace-fail "_LOCALHOST = 'localhost'" "_LOCALHOST = '127.0.0.1'"
  '';
})
