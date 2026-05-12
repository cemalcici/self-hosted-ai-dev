from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def read(rel_path: str) -> str:
    return (REPO_ROOT / rel_path).read_text()


def exists(rel_path: str) -> bool:
    return (REPO_ROOT / rel_path).exists()


def test_repo_managed_preset_is_removed() -> None:
    assert not exists("config/oh-my-opencode-slim.jsonc"), (
        "Runtime preset authority must not live in the repository anymore"
    )


def test_compose_no_longer_bind_mounts_repo_preset() -> None:
    compose = read("docker-compose.yml")
    assert "oh-my-opencode-slim.jsonc" not in compose, (
        "Compose must stop bind-mounting a repo-managed preset file"
    )


def test_opencode_bootstrap_does_not_copy_repo_preset() -> None:
    script = read("scripts/opencode-entrypoint.sh")
    assert "/app/config/oh-my-opencode-slim.jsonc" not in script
    assert "cp \"$REPO_PLUGIN_CONFIG_TEMPLATE\"" not in script


def test_opencode_bootstrap_migrates_legacy_plugins_key() -> None:
    script = read("scripts/opencode-entrypoint.sh")
    # Bootstrap path must use "plugin" (not "plugins") in the heredoc
    assert '"plugin":' in script, (
        "Bootstrap must use correct 'plugin' key in heredoc"
    )
    # Must contain migration logic for existing legacy configs
    assert 'grep -q' in script and '"plugins"' in script, (
        "Entrypoint must handle migration of legacy 'plugins' key"
    )


def test_runtime_processes_drop_to_aidev() -> None:
    opencode = read("scripts/opencode-entrypoint.sh")
    openchamber = read("scripts/openchamber-entrypoint-wrapper.sh")
    assert "runuser -u aidev --" in opencode
    assert "runuser -u \"$USER\" --" in openchamber


if __name__ == "__main__":
    test_repo_managed_preset_is_removed()
    test_compose_no_longer_bind_mounts_repo_preset()
    test_opencode_bootstrap_does_not_copy_repo_preset()
    test_opencode_bootstrap_migrates_legacy_plugins_key()
    test_runtime_processes_drop_to_aidev()
    print("runtime user regression checks passed")