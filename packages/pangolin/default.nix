{ lib
, fetchFromGitHub
, esbuild
, buildNpmPackage
, makeWrapper
, formats
, nodejs_22
,
}:

buildNpmPackage (finalAttrs: {
  pname = "pangolin";
  version = "1.22.2";

  __structuredAttrs = true;
  enableParallelBuilding = true;

  src = fetchFromGitHub {
    owner = "fosrl";
    repo = "pangolin";
    tag = finalAttrs.version;
    hash = "sha256-FNEw1qOX1s3vO9WQIbgspNAGwPzS2cyUb2HiS0RHaAg=";
  };

  # Keep the runtime ABI aligned with better-sqlite3 11.9.1.
  nodejs = nodejs_22;
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-BRUNkfSbvuzo2iR25WdNGlr47UErjwJl31oKQ815vWg=";
  npmFlags = [ "--legacy-peer-deps" ];

  nativeBuildInputs = [
    esbuild
    makeWrapper
  ];

  postUnpack = ''
    rm -rf server/private
  '';

  prePatch = ''
    substituteInPlace server/lib/consts.ts --replace-fail \
      'export const APP_VERSION = "1.22.0";' \
      'export const APP_VERSION = "${finalAttrs.version}";'
  '';

  preBuild = ''
    npm run set:sqlite
    npm run set:oss
    npm run db:generate
  '';

  buildPhase = ''
    runHook preBuild

    npm run build
    npm run build:cli

    runHook postBuild
  '';

  preInstall = "mkdir -p $out/{bin,share/pangolin}";

  installPhase = ''
    runHook preInstall

    cp -r node_modules $out/share/pangolin/node_modules
    cp -r .next/standalone/. $out/share/pangolin
    cp -r .next/static $out/share/pangolin/.next/static
    cp -r dist $out/share/pangolin/dist
    cp -r server/migrations $out/share/pangolin/dist/init
    cp package.json $out/share/pangolin/package.json

    cp server/db/names.json $out/share/pangolin/dist/names.json
    cp server/db/ios_models.json $out/share/pangolin/dist/ios_models.json
    cp server/db/mac_models.json $out/share/pangolin/dist/mac_models.json

    cp -r public $out/share/pangolin/public

    runHook postInstall
  '';

  preFixup =
    let
      defaultConfig = (formats.yaml { }).generate "pangolin-default-config" {
        app.dashboard_url = "https://pangolin.example.test";
        domains.domain1.base_domain = "example.test";
        gerbil.base_endpoint = "pangolin.example.test";
        server.secret = "A secret string used for encrypting sensitive data. Must be at least 8 characters long.";
      };
      commonVariables = "--set NODE_OPTIONS enable-source-maps --set NODE_ENV development --set ENVIRONMENT prod";
      serverSetup = ''
        test "$(readlink .next/.nix-package)" = "${placeholder "out"}" || { { test ! -d .next || chmod -R u+w .next; } && rm -rf .next && cp -r ${placeholder "out"}/share/pangolin/.next . && chmod -R u+w .next && ln -s ${placeholder "out"} .next/.nix-package; } &&
        test -f public/.nix_skip_setup || { rm -f public && ln -s ${placeholder "out"}/share/pangolin/public .; } &&
        test -f node_modules/.nix_skip_setup || { rm -f node_modules && ln -s ${placeholder "out"}/share/pangolin/node_modules .; } &&
        test -f config/config.yml || { install -Dm600 ${defaultConfig} config/config.yml && { test -z "$EDITOR" && { echo "Please edit $(pwd)/config/config.yml and run the server again."; exit 255; } || "$EDITOR" config/config.yml; }; } &&
        command ${placeholder "out"}/bin/migrate-pangolin-database
      '';
    in
    ''
      makeWrapper $out/share/pangolin/dist/cli.mjs $out/bin/pangctl ${commonVariables}
      makeWrapper $out/share/pangolin/dist/migrations.mjs $out/bin/migrate-pangolin-database ${commonVariables}
      makeWrapper $out/share/pangolin/dist/server.mjs $out/bin/pangolin ${commonVariables} --run '${serverSetup}'
    '';

  meta = {
    description = "Tunneled reverse proxy server with identity and access control";
    homepage = "https://github.com/fosrl/pangolin";
    changelog = "https://github.com/fosrl/pangolin/releases/tag/${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "pangolin";
  };
})
