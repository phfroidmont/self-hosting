{ writeShellApplication, borgbackup }:
# A `borg` that accepts the warnings live services cause during `borg create`:
# 100 (a file changed while it was read) and 107 (a file vanished before it was
# read). The archive is still written and holds everything else. Any other
# warning or error fails as before, and so does a run with several kinds of
# warnings, which borg reports as the generic 1.
writeShellApplication {
  name = "borg";
  text = ''
    export BORG_EXIT_CODES=modern
    status=0
    ${borgbackup}/bin/borg "$@" || status=$?
    if [ "''${1:-}" = create ] && { [ "$status" -eq 100 ] || [ "$status" -eq 107 ]; }; then
      echo "borg create ended with warning $status (file changed or vanished during the backup); accepting the archive" >&2
      exit 0
    fi
    exit "$status"
  '';
}
