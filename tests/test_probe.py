"""Primitive probes must retain the native process's actual output and exit."""
from scripts.mdl_probe import probe_case


def test_probe_case_uses_clean_quit_and_records_output(tmp_path):
    executable = tmp_path / "fake-mdli"
    executable.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "print('Banner <WARRANTY>')\n"
        "print('LISTENING-AT-LEVEL 1 PROCESS 1')\n"
        "for line in sys.stdin:\n"
        "    if line.strip() == '<QUIT>': break\n"
        "    print('VALUE:' + line.strip())\n",
        encoding="utf-8",
    )
    executable.chmod(0o755)
    result = probe_case(executable, tmp_path,
                        {"name": "arithmetic", "expression": "<+ 1 2>"}, 2)
    assert result["ok"]
    assert result["exit_code"] == 0
    assert result["stdout"].startswith("Banner <WARRANTY>\n")
    assert result["result_output"] == "VALUE:<+ 1 2>\n"
    assert result["stderr"] == ""
    assert result["input"] == "<+ 1 2>\n<QUIT>\n"
