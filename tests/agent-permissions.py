"""Offline checks: policy precedence and the installed SDK command surface."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib


def run(*args, env=None):
    return subprocess.run(args, env=env, capture_output=True, text=True, timeout=30)


fixture = json.loads(Path(sys.argv[1]).read_text())
policy = fixture["policy"]
sdk = Path(sys.argv[2])
prefixes = [["gcloud", "pam"], ["gcloud", "alpha", "pam"], ["gcloud", "beta", "pam"]]
files = fixture["managedFiles"]
# A Copilot managed policy with any rule makes every unmatched operation ask.
assert set(files) == {"codex/requirements.toml", "claude-code/managed-settings.json"}, set(files)
for file in files.values():
    assert (file["mode"], file["user"], file["group"]) == ("0444", "root", "root")

requirements = tomllib.loads(files["codex/requirements.toml"]["text"])
rules = requirements["rules"]["prefix_rules"]
assert [rule["pattern"] for rule in rules] == [
    [{"token": token} for token in prefix] for prefix in prefixes
]
assert all(rule["decision"] == "forbidden" for rule in rules)
assert files["codex/requirements.toml"]["text"] == policy["codexRequirements"]

permissions = json.loads(files["claude-code/managed-settings.json"]["text"])["permissions"]
assert permissions["deny"] == [
    pattern
    for prefix in prefixes
    for pattern in (f"Bash({' '.join(prefix)})", f"Bash({' '.join(prefix)} *)")
]
assert permissions["disableBypassPermissionsMode"] == "disable"

with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    deny = directory / "deny.rules"
    deny.write_text(policy["codexRules"])
    allow = directory / "repo.rules"
    allow.write_text('prefix_rule(pattern = ["gcloud"], decision = "allow")\n')

    for prefix in prefixes:
        for suffix in [[], ["grants", "create", "--help"]]:
            result = run("codex", "execpolicy", "check", "--rules", str(deny),
                         "--rules", str(allow), "--", *prefix, *suffix)
            assert result.returncode == 0, result.stderr
            assert json.loads(result.stdout)["decision"] == "forbidden", result.stdout

    environment = os.environ | {
        "CLOUDSDK_CONFIG": str(directory / "gcloud"),
        "CLOUDSDK_CORE_DISABLE_PROMPTS": "1",
    }
    blocked = [prefix[1:] + ["--help"] for prefix in prefixes] + [
        ["--project=permission-test", "pam", "grants", "create", "--help"],
        ["--project", "permission-test", "beta", "pam", "--help"],
        ["pam", "--format=json", "--help"],
    ]
    for args in blocked:
        result = run(str(sdk / "bin/gcloud"), *args, env=environment)
        assert result.returncode != 0, (args, result.stdout)
        assert "Invalid choice: 'pam'" in result.stderr, (args, result.stderr)

    for args in [["version", "--format=json"], ["auth", "list", "--help"],
                 ["container", "clusters", "get-credentials", "--help"]]:
        result = run(str(sdk / "bin/gcloud"), *args, env=environment)
        assert result.returncode == 0, result.stderr
        result = run("codex", "execpolicy", "check", "--rules", str(deny),
                     "--rules", str(allow), "--", "gcloud", *args)
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)["decision"] == "allow", result.stdout

    assert (sdk / "bin/gke-gcloud-auth-plugin").is_file()
    for path in ["pam", "alpha/pam", "beta/pam"]:
        assert not (sdk / "google-cloud-sdk/lib/surface" / path).exists()

print("Managed policies, Codex deny precedence, and PAM-disabled SDK checks passed.")
