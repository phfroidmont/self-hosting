source_db=$1
snapshot=$2

umask 077
echo "Grafana backup: creating SQLite snapshot from $source_db"
if [ ! -s "$source_db" ]; then
  echo "Grafana backup: source database is missing or empty" >&2
  exit 1
fi

temporary=$(mktemp "${snapshot}.tmp.XXXXXX")
cleanup() {
  rm -f "$temporary" "$temporary-journal" "$temporary-wal" "$temporary-shm"
}
trap cleanup EXIT

# The online backup API includes committed WAL data without stopping Grafana.
# Bound the whole operation as SQLite's backup can retry while writers are busy.
timeout 60s sqlite3 -readonly -cmd '.timeout 10000' "$source_db" ".backup '$temporary'"
integrity=$(sqlite3 -readonly "$temporary" 'PRAGMA quick_check;')
if [ "$integrity" != ok ]; then
  echo "Grafana backup: snapshot integrity check failed: $integrity" >&2
  exit 1
fi
tables=$(sqlite3 -readonly "$temporary" "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name IN ('user', 'dashboard', 'data_source');")
if [ "$tables" != 3 ]; then
  echo "Grafana backup: snapshot is missing expected Grafana tables" >&2
  exit 1
fi

mv -f "$temporary" "$snapshot"
echo "Grafana backup: validated snapshot published at $snapshot"
