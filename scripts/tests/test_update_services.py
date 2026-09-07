import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "update_services.sh"
DOCKER_STUB = """#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
if args[:2] != ["compose", "-f"]:
    sys.exit(90)
args = args[3:]
with open(os.environ["UPDATE_TEST_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[0] == "config":
    print(os.environ["UPDATE_TEST_CONFIG"])
    sys.exit(int(os.environ.get("UPDATE_TEST_CONFIG_EXIT", "0")))
elif args[0] == "ps":
    if "--services" in args:
        print(os.environ["UPDATE_TEST_RUNNING"])
elif args[0] == "pull":
    sys.exit(int(os.environ.get("UPDATE_TEST_PULL_EXIT", "0")))
elif args[0] == "up":
    sys.exit(int(os.environ.get("UPDATE_TEST_UP_EXIT", "0")))
else:
    sys.exit(91)
"""


class UpdateServicesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="envkit update test ")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        docker = self.directory / "docker"
        docker.write_text(DOCKER_STUB)
        docker.chmod(0o755)
        self.log = self.directory / "calls.jsonl"
        self.env = {
            **os.environ,
            "PATH": str(self.directory) + os.pathsep + os.environ["PATH"],
            "UPDATE_TEST_LOG": str(self.log),
            "UPDATE_TEST_RUNNING": "vault\ngitea\ncaddy",
            "UPDATE_TEST_CONFIG": json.dumps({"services": {
                "vault": {"image": "vaultwarden/server:latest"},
                "gitea": {"image": "gitea/gitea:latest-rootless"},
                "qbit": {"image": "qbittorrentofficial/qbittorrent-nox:latest"},
                "jellyfin": {"image": "lscr.io/linuxserver/jellyfin:latest"},
                "pinned": {"image": "example/app:1.2.3"},
                "digest": {"image": "example/app:latest@sha256:abc"},
                "caddy": {"image": "my-caddy", "build": {"context": "."}},
                "other": {"image": "example/notlatest:stable"},
            }}),
        }

    def invoke(self, *args, input=""):
        result = subprocess.run(
            ["bash", str(SCRIPT), *args], env=self.env, cwd=self.directory,
            input=input, text=True, capture_output=True, timeout=10,
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, calls

    def mutations(self, calls):
        return [call for call in calls if call[0] in ("pull", "up")]

    def test_preview_is_read_only(self):
        result, calls = self.invoke("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(calls), [])
        self.assertIn("pull vault gitea qbit jellyfin", result.stdout)
        self.assertIn("--wait-timeout 120 vault gitea", result.stdout)
        self.assertIn("qbit: pull image only; keep stopped", result.stdout)

    def test_updates_latest_variants_without_starting_stopped_services(self):
        result, calls = self.invoke("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(calls), [
            ["pull", "vault", "gitea", "qbit", "jellyfin"],
            ["up", "-d", "--no-deps", "--no-build", "--pull", "never",
             "--wait", "--wait-timeout", "120", "vault", "gitea"],
        ])

    def test_service_selection_and_deduplication(self):
        result, calls = self.invoke("--yes", "vault", "vault")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(calls)[0], ["pull", "vault"])
        self.assertEqual(self.mutations(calls)[1][-1], "vault")
        self.assertNotIn("gitea", self.mutations(calls)[1])

    def test_rejects_non_latest_services_before_changes(self):
        result, calls = self.invoke("--yes", "vault", "pinned")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.mutations(calls), [])

    def test_cancelling_does_not_pull(self):
        result, calls = self.invoke(input="n\n")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.mutations(calls), [])

    def test_noninteractive_use_requires_confirmation(self):
        result, calls = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.mutations(calls), [])

    def test_pull_failure_does_not_recreate(self):
        self.env["UPDATE_TEST_PULL_EXIT"] = "1"
        result, calls = self.invoke("--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[0] for call in self.mutations(calls)], ["pull"])

    def test_config_failure_does_not_update(self):
        self.env["UPDATE_TEST_CONFIG_EXIT"] = "1"
        result, calls = self.invoke("--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.mutations(calls), [])

    def test_unhealthy_upgrade_is_reported_as_failure(self):
        self.env["UPDATE_TEST_UP_EXIT"] = "1"
        result, calls = self.invoke("--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("[OK]", result.stdout)

    def test_only_pulls_when_all_selected_services_are_stopped(self):
        self.env["UPDATE_TEST_RUNNING"] = "caddy"
        result, calls = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in self.mutations(calls)], ["pull"])

    def test_no_matching_services_is_a_noop(self):
        self.env["UPDATE_TEST_CONFIG"] = '{"services": {}}'
        result, calls = self.invoke("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(calls), [])

    def test_untagged_images_and_registry_ports(self):
        self.env["UPDATE_TEST_CONFIG"] = json.dumps({"services": {
            "implicit": {"image": "registry.example:5000/app"},
            "explicit": {"image": "registry.example:5000/app:latest"},
            "fixed": {"image": "registry.example:5000/app:1.0"},
        }})
        result, calls = self.invoke("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(calls), [["pull", "implicit", "explicit"]])


if __name__ == "__main__":
    unittest.main()
