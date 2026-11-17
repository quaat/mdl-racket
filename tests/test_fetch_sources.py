"""A local fake Git repository verifies fetch logic without internet."""
from __future__ import annotations

import subprocess
from pathlib import Path

from scripts import fetch_sources


def git(*argv: str, cwd: Path) -> str:
    result = subprocess.run(["git", *argv], cwd=cwd, text=True,
                            check=True, capture_output=True)
    return result.stdout.strip()


def test_acquire_first_time_and_modified_refusal(tmp_path, monkeypatch):
    origin = tmp_path / "origin"
    origin.mkdir()
    git("init", "-q", cwd=origin)
    git("config", "user.name", "Tester", cwd=origin)
    git("config", "user.email", "test@example.invalid", cwd=origin)
    (origin / "code.mdl").write_text("<DEFINE TEST () 1>\n")
    git("add", "code.mdl", cwd=origin)
    git("commit", "-qm", "source", cwd=origin)
    sha = git("rev-parse", "HEAD", cwd=origin)
    monkeypatch.setattr(fetch_sources, "CACHE", tmp_path / "cache")
    info = fetch_sources.acquire("source", {"url": str(origin), "commit": sha}, update=False)
    assert info["commit"] == sha
    assert (tmp_path / "cache/source/code.mdl").exists()
    (tmp_path / "cache/source/code.mdl").write_text("changed")
    try:
        fetch_sources.acquire("source", {"url": str(origin), "commit": sha}, update=False)
    except RuntimeError as error:
        assert "modified upstream" in str(error)
    else:
        raise AssertionError("modified checkout must not be replaced")
