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
  '';
})
