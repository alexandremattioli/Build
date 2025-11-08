import subprocess, sys


def run(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def test_py_compile_scripts():
    for path in [
        'scripts/bootstrap/ubuntu24/peer_agent.py',
        'scripts/bootstrap/ubuntu24/advisor.py',
        'scripts/bootstrap/ubuntu24/message_bridge.py',
    ]:
        r = run([sys.executable, '-m', 'py_compile', path])
        assert r.returncode == 0, f"py_compile failed for {path}: {r.stderr}"


def test_advisor_help_exits_zero():
    r = run([sys.executable, 'scripts/bootstrap/ubuntu24/advisor.py', '--help'])
    assert r.returncode == 0
    assert 'usage' in (r.stdout + r.stderr).lower()


def test_message_bridge_runs():
    r = run([sys.executable, 'scripts/bootstrap/ubuntu24/message_bridge.py', 'identity_assigned', '{"hostname":"x","role":"y"}'])
    assert r.returncode == 0
