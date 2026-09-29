from contextlib import closing
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading


snapshot_command, patterns_file, restore_check = sys.argv[1:]


def run(*args, success=True, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if success:
        assert result.returncode == 0, (args, result.stdout, result.stderr)
    else:
        assert result.returncode != 0, args
    return result


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    live = root / "nix/var/data/grafana/data"
    live.mkdir(parents=True)
    backup = root / "nix/var/data/backup"
    backup.mkdir(parents=True)
    source = live / "grafana.db"
    snapshot = backup / "grafana.sqlite"
    db = sqlite3.connect(source)
    db.executescript("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE user (id INTEGER PRIMARY KEY);
        CREATE TABLE dashboard (id INTEGER PRIMARY KEY);
        CREATE TABLE data_source (id INTEGER PRIMARY KEY);
        INSERT INTO dashboard VALUES (1);
    """)
    stop = threading.Event()
    started = threading.Event()
    errors = []

    def writer():
        try:
            with closing(sqlite3.connect(source)) as connection:
                while not stop.is_set():
                    connection.execute("INSERT INTO dashboard DEFAULT VALUES")
                    connection.commit()
                    started.set()
                    stop.wait(0.005)
        except Exception as error:
            errors.append(error)
            started.set()

    thread = threading.Thread(target=writer)
    thread.start()
    try:
        assert started.wait(5)
        run(snapshot_command, str(source), str(snapshot))
    finally:
        stop.set()
        thread.join()
    assert not errors, errors
    assert snapshot.stat().st_mode & 0o777 == 0o600
    with closing(sqlite3.connect(snapshot)) as copy:
        assert copy.execute("PRAGMA quick_check").fetchone() == ("ok",)
        assert copy.execute("SELECT count(*) FROM dashboard").fetchone()[0] >= 2
    db.close()
    original = snapshot.read_bytes()

    # Missing, invalid and empty-schema sources cannot replace the last snapshot.
    for name in ("missing.db", "corrupt.db", "empty-schema.db"):
        candidate = root / name
        if name == "corrupt.db":
            candidate.write_bytes(b"not a database")
        elif name == "empty-schema.db":
            with closing(sqlite3.connect(candidate)) as empty:
                empty.execute("VACUUM")
        run(snapshot_command, str(candidate), str(snapshot), success=False)
        assert snapshot.read_bytes() == original
        assert not list(backup.glob("*.tmp.*"))

    # An exclusive rollback-journal lock must fail within the overall timeout.
    lock = sqlite3.connect(source)
    lock.execute("PRAGMA journal_mode=DELETE")
    lock.execute("BEGIN EXCLUSIVE")
    try:
        run(snapshot_command, str(source), str(snapshot), success=False, timeout=70)
    finally:
        lock.rollback()
        lock.close()
    assert snapshot.read_bytes() == original
    assert not list(backup.glob("*.tmp.*"))

    # Exercise the real exclusions with Borg, including journal sidecars and logs.
    for suffix in ("-wal", "-shm", "-journal"):
        Path(str(source) + suffix).write_text("volatile")
    (live / "log").mkdir()
    (live / "log/grafana.log").write_text("volatile")
    (live / "keep-me").write_text("other Grafana data")
    patterns = root / "patterns"
    patterns.write_text(Path(patterns_file).read_text().replace("/nix/var/data", str(root / "nix/var/data")))
    repo = root / "repo"
    run("borg", "init", "--encryption=none", str(repo))
    archive = f"{repo}::test"
    run("borg", "create", "--patterns-from", str(patterns), archive, str(root / "nix/var/data"))
    entries = run("borg", "list", "--short", archive).stdout.splitlines()
    assert str(snapshot).lstrip("/") in entries
    assert str(live / "keep-me").lstrip("/") in entries
    assert not any("grafana.db" in entry or "/log" in entry for entry in entries)

    extracted = root / "extracted"
    extracted.mkdir()
    run("borg", "extract", archive, cwd=extracted)
    restore_root = extracted / str(root).lstrip("/")
    environment = dict(os.environ, restore_dir=str(restore_root))
    run(restore_check, env=environment)
    restored = restore_root / "nix/var/data/backup/grafana.sqlite"
    restored.write_bytes(b"corrupt")
    run(restore_check, env=environment, success=False)
    restored.unlink()
    with closing(sqlite3.connect(restored)) as empty:
        empty.execute("VACUUM")
    run(restore_check, env=environment, success=False)

print("Grafana snapshot, failure handling, Borg exclusions and restore checks passed")
