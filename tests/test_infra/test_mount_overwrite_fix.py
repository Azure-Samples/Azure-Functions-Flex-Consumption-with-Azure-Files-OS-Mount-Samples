"""
Tests for the plural azure-files-mounts.bicep module and the deploy script
fix that prevents the mount-overwrite bug.

The bug: deploying mounts one at a time via azure-files-mount.bicep (singular)
causes Microsoft.Web/sites/config to REPLACE the azureStorageAccounts dict on
each deployment.  Only the last mount survives.

The fix: azure-files-mounts.bicep (plural) accepts an array and deploys all
mounts in a single config resource.  deploy-sample.sh now calls this module
once instead of looping.
"""

import pathlib
import shutil
import subprocess

import pytest


REPO_ROOT = pathlib.Path(__file__).parent.parent.parent

az_available = shutil.which("az") is not None


class TestPluralMountsModule:
    """Validate the new azure-files-mounts.bicep (plural) module."""

    def test_plural_module_exists(self):
        """The plural mounts module must exist at infra/modules/azure-files-mounts.bicep."""
        module = REPO_ROOT / "infra" / "modules" / "azure-files-mounts.bicep"
        assert module.exists(), (
            "azure-files-mounts.bicep (plural) not found — the mount overwrite fix is missing"
        )

    def test_singular_module_still_exists(self):
        """The original singular module should remain for backward compatibility."""
        module = REPO_ROOT / "infra" / "modules" / "azure-files-mount.bicep"
        assert module.exists(), (
            "azure-files-mount.bicep (singular) was removed — it should be kept for "
            "backward-compatible single-mount scenarios"
        )

    @pytest.mark.skipif(not az_available, reason="Azure CLI not found")
    def test_plural_module_compiles(self):
        """azure-files-mounts.bicep must compile without errors."""
        module = REPO_ROOT / "infra" / "modules" / "azure-files-mounts.bicep"
        result = subprocess.run(
            ["az", "bicep", "build", "--file", str(module)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"Bicep compilation failed for azure-files-mounts.bicep:\n"
            f"STDERR: {result.stderr}\nSTDOUT: {result.stdout}"
        )

    def test_plural_module_accepts_array_param(self):
        """The plural module must declare a 'mounts' parameter of type array."""
        module = REPO_ROOT / "infra" / "modules" / "azure-files-mounts.bicep"
        content = module.read_text(encoding="utf-8")
        assert "param mounts array" in content, (
            "azure-files-mounts.bicep must accept a 'mounts' array parameter"
        )

    def test_plural_module_uses_single_config_resource(self):
        """The module should deploy exactly ONE Microsoft.Web/sites/config resource."""
        module = REPO_ROOT / "infra" / "modules" / "azure-files-mounts.bicep"
        content = module.read_text(encoding="utf-8")
        config_count = content.count("Microsoft.Web/sites/config")
        assert config_count == 1, (
            f"Expected exactly 1 Microsoft.Web/sites/config resource, found {config_count}. "
            "Multiple config resources would re-introduce the overwrite bug."
        )

    def test_plural_module_enforces_azure_files_type(self):
        """Each mount entry must set type to AzureFiles."""
        module = REPO_ROOT / "infra" / "modules" / "azure-files-mounts.bicep"
        content = module.read_text(encoding="utf-8")
        assert "'AzureFiles'" in content, (
            "Module must set type: 'AzureFiles' for Flex Consumption OS mounts"
        )


class TestDeployScriptMountFix:
    """Verify the deploy script uses the plural module instead of sequential mounts."""

    def _read_deploy_script(self) -> str:
        script = REPO_ROOT / "infra" / "scripts" / "deploy-sample.sh"
        assert script.exists(), "deploy-sample.sh not found"
        return script.read_text(encoding="utf-8")

    def test_deploy_script_references_plural_module(self):
        """deploy-sample.sh must reference azure-files-mounts.bicep (plural)."""
        content = self._read_deploy_script()
        assert "azure-files-mounts.bicep" in content, (
            "deploy-sample.sh does not reference the plural mounts module"
        )

    def test_deploy_script_no_sequential_mount_deployments(self):
        """deploy-sample.sh must NOT deploy mounts one at a time via the singular module."""
        content = self._read_deploy_script()
        # The old pattern used --name "mount-data" and --name "mount-tools" as
        # separate az deployment group create calls.
        assert content.count("azure-files-mount.bicep") == 0, (
            "deploy-sample.sh still references the singular azure-files-mount.bicep — "
            "this causes the overwrite bug where only the last mount survives"
        )

    def test_deploy_script_single_mount_deployment(self):
        """deploy-sample.sh should configure all mounts in a single deployment call."""
        content = self._read_deploy_script()
        # Count actual --template-file references to the plural module (not comments)
        mount_deploys = content.count("--template-file")
        template_lines = [
            line.strip()
            for line in content.splitlines()
            if "--template-file" in line and "azure-files-mounts.bicep" in line
        ]
        assert len(template_lines) == 1, (
            f"Expected exactly 1 --template-file deployment of azure-files-mounts.bicep, "
            f"found {len(template_lines)}"
        )

    def test_deploy_script_passes_both_mounts(self):
        """The single deployment call must include both 'data' and 'tools' mounts."""
        content = self._read_deploy_script()
        assert '"data"' in content or "'data'" in content, (
            "deploy-sample.sh mount config is missing the 'data' share"
        )
        assert '"tools"' in content or "'tools'" in content, (
            "deploy-sample.sh mount config is missing the 'tools' share"
        )

    def test_deploy_script_mount_paths_start_with_mounts(self):
        """All mount paths must start with /mounts/ per Flex Consumption requirement."""
        content = self._read_deploy_script()
        assert "/mounts/data" in content, "Missing /mounts/data path"
        assert "/mounts/tools" in content, "Missing /mounts/tools path"
