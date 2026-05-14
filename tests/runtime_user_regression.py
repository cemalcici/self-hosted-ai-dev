from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def read(rel_path: str) -> str:
    return (REPO_ROOT / rel_path).read_text()


def exists(rel_path: str) -> bool:
    return (REPO_ROOT / rel_path).exists()


def test_repo_managed_preset_exists_as_jsonc() -> None:
    assert exists("config/oh-my-opencode-slim.jsonc"), (
        "The hybrid model requires a repo-managed .jsonc preset file"
    )


def test_compose_bind_mounts_repo_preset_file() -> None:
    compose = read("docker-compose.yml")
    assert "./config/oh-my-opencode-slim.jsonc:/home/aidev/.config/opencode/oh-my-opencode-slim.jsonc" in compose, (
        "Compose must bind-mount the repo-managed preset file into the runtime config directory"
    )


def test_opencode_bootstrap_does_not_copy_repo_preset() -> None:
    script = read("scripts/opencode-entrypoint.sh")
    assert "/app/config/oh-my-opencode-slim.jsonc" not in script
    assert "cp \"$REPO_PLUGIN_CONFIG_TEMPLATE\"" not in script


def test_opencode_bootstrap_heredoc_uses_plugin_key() -> None:
    script = read("scripts/opencode-entrypoint.sh")
    # Bootstrap path must use "plugin" (not "plugins") in the heredoc
    assert '"plugin":' in script, (
        "Bootstrap must use correct 'plugin' key in heredoc"
    )


def test_opencode_bootstrap_migrates_legacy_plugins_key() -> None:
    script = read("scripts/opencode-entrypoint.sh")
    # Must contain migration logic for existing legacy configs
    assert 'grep -q' in script and '"plugins"' in script, (
        "Entrypoint must handle migration of legacy 'plugins' key"
    )


def test_runtime_processes_drop_to_aidev() -> None:
    opencode = read("scripts/opencode-entrypoint.sh")
    openchamber = read("scripts/openchamber-entrypoint-wrapper.sh")
    assert "runuser -u aidev --" in opencode
    assert "runuser -u \"$USER\" --" in openchamber


def test_dockerfile_installs_nano_editor() -> None:
    dockerfile = read("Dockerfile")
    assert "nano" in dockerfile, "Runtime image must install nano for README workflow"


def test_readme_points_to_real_preset_file() -> None:
    readme = read("README.md")
    assert "nano ./config/oh-my-opencode-slim.jsonc" in readme, (
        "README must show the host-side nano command for the repo-managed preset"
    )


if __name__ == "__main__":
    test_repo_managed_preset_exists_as_jsonc()
    test_compose_bind_mounts_repo_preset_file()
    test_opencode_bootstrap_does_not_copy_repo_preset()
    test_opencode_bootstrap_heredoc_uses_plugin_key()
    test_opencode_bootstrap_migrates_legacy_plugins_key()
    test_runtime_processes_drop_to_aidev()
    test_dockerfile_installs_nano_editor()
    test_readme_points_to_real_preset_file()
    print("runtime user regression checks passed")
