{ lib
, buildGoModule
, fetchFromGitHub
, versionCheckHook
}:

buildGoModule (finalAttrs: {
  pname = "olm";
  version = "1.8.2";

  src = fetchFromGitHub {
    owner = "fosrl";
    repo = "olm";
    tag = finalAttrs.version;
    hash = "sha256-4uHRWAgJzDBnPXi4XyzsAUgNp+l5R7anUD7sfoYLY/k=";
  };

  vendorHash = "sha256-L0d7rrl4nFX8bZrFxCsWeO24Dou94ELwSOhRzg2+w6I=";
  subPackages = [ "." ];

  # Keep the native client; only remove the unsolicited update request and
  # the CLI's hardcoded, unauthenticated profiling listener on :4444.
  postPatch = ''
    substituteInPlace main.go \
      --replace-fail '"github.com/fosrl/newt/updates"' "" \
      --replace-fail $'if err := updates.CheckForUpdate("fosrl", "olm", config.Version); err != nil {\n\t\tlogger.Debug("Failed to check for updates: %v", err)\n\t}' "" \
      --replace-fail 'PprofAddr:    ":4444", // TODO: REMOVE OR MAKE CONFIGURABLE' 'PprofAddr:    "", // Disabled in the packaged CLI.'
  '';

  ldflags = [ "-s" "-w" "-X=main.olmVersion=${finalAttrs.version}" ];
  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Native Pangolin WireGuard client";
    homepage = "https://github.com/fosrl/olm";
    changelog = "https://github.com/fosrl/olm/releases/tag/${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "olm";
    platforms = lib.platforms.linux;
  };
})
