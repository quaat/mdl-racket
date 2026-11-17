"""Proves that the PTY harness can capture a scripted prompt/response protocol.

This is **not** evidence that Confusion itself uses exactly that protocol.
"""
from scripts import reference_runner


def test_reference_runner_with_fake_interpreter(tmp_path, monkeypatch):
    executable = tmp_path / "fake-mdli"
    executable.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.stdout.write('Welcome <WARRANTY> and <COPYING>\\nReady\\n>')\n"
        "sys.stdout.flush()\n"
        "for line in sys.stdin:\n"
        "    sys.stdout.write('RESULT:' + line.strip() + '\\n>')\n"
        "    sys.stdout.flush()\n",
        encoding="utf-8",
    )
    executable.chmod(0o755)
    game_image = tmp_path / "SAVEFILE" / "ZORK.SAVE"
    game_image.parent.mkdir()
    game_image.write_bytes(b"fake-test-only")
    monkeypatch.setattr(reference_runner, "GAME", tmp_path)
    monkeypatch.setattr(reference_runner, "EXE", executable)
    monkeypatch.setattr(reference_runner, "IMAGE", game_image)
    result = reference_runner.capture({"name": "pty-test", "commands": ["look", "north"]}, timeout=2)
    assert result["complete"], result["error"]
    assert "Welcome <WARRANTY> and <COPYING>\nReady\n" == result["initial_output"]
    assert result["commands"][0]["input"] == "look"
    assert "RESULT:look" in result["commands"][0]["output"]
    assert "RESULT:north" in result["commands"][1]["output"]
    assert result["commands"][0]["output"] == "RESULT:look\n"
    assert result["commands"][1]["output"] == "RESULT:north\n"
