{ lib
, buildGoModule
, fetchFromGitHub
, versionCheckHook
,
}:

buildGoModule (finalAttrs: {
  pname = "newt";
  version = "1.16.0";

  src = fetchFromGitHub {
    owner = "fosrl";
    repo = "newt";
    tag = finalAttrs.version;
    hash = "sha256-Ehmo7RUbZDZhBYAmaheh6IT01rhDj3LsQrXbaYQpSxg=";
  };

  vendorHash = "sha256-JhNBJhj5YX3Wurv7r/JDu6YtHizOMLk+NCob7ISx+3c=";

  ldflags = [
    "-s"
    "-w"
    "-X=main.newtVersion=${finalAttrs.version}"
  ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  __structuredAttrs = true;

  meta = {
    description = "Tunneling client for Pangolin";
    homepage = "https://github.com/fosrl/newt";
    changelog = "https://github.com/fosrl/newt/releases/tag/${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "newt";
  };
})
