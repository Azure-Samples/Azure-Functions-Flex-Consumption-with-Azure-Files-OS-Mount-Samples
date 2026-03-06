"""
Bicep template validation tests.

Validates that all .bicep files in the repository are syntactically correct
by running `az bicep build`. This is a CI validation step, not a unit test
in the traditional sense — but it catches syntax errors before deployment.

Requirements:
- Azure CLI must be installed with the bicep extension.
- This test is skipped in CI if az CLI is not available.

Note (Zoe): Integration tests that actually deploy Bicep templates are
out of scope for now. This only validates syntax/compilation.
"""

import pathlib
import shutil
import subprocess

import pytest


REPO_ROOT = pathlib.Path(__file__).parent.parent.parent


def find_bicep_files() -> list[pathlib.Path]:
    """Find all .bicep files in the repository."""
    return sorted(REPO_ROOT.rglob("*.bicep"))


# Skip all tests if az CLI is not available
az_available = shutil.which("az") is not None
pytestmark = pytest.mark.skipif(
    not az_available,
    reason="Azure CLI (az) not found — skipping Bicep validation",
)


class TestBicepValidation:
    """Validate Bicep template syntax via az bicep build."""

    def test_bicep_files_exist(self):
        """
        There should be at least some .bicep files in the repo.
        If there aren't, either the infra hasn't been written yet
        or something is wrong with the repo structure.
        """
        bicep_files = find_bicep_files()
        if len(bicep_files) == 0:
            pytest.skip(
                "No .bicep files found yet — infra code not written. "
                "This test will run once Bicep files are added."
            )

    @pytest.mark.parametrize(
        "bicep_file",
        find_bicep_files(),
        ids=[str(f.relative_to(REPO_ROOT)) for f in find_bicep_files()],
    )
    def test_bicep_file_compiles(self, bicep_file: pathlib.Path):
        """Each .bicep file should compile without errors."""
        result = subprocess.run(
            ["az", "bicep", "build", "--file", str(bicep_file)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"Bicep compilation failed for {bicep_file.relative_to(REPO_ROOT)}:\n"
            f"STDERR: {result.stderr}\n"
            f"STDOUT: {result.stdout}"
        )

    def test_shared_modules_exist(self):
        """
        Shared infra modules should be present at infra/modules/.
        Skip if not yet created.
        """
        modules_dir = REPO_ROOT / "infra" / "modules"
        if not modules_dir.exists():
            pytest.skip("infra/modules/ not yet created")

        bicep_files = list(modules_dir.glob("*.bicep"))
        assert len(bicep_files) > 0, (
            "infra/modules/ exists but contains no .bicep files"
        )

    def test_sample_infra_references_shared_modules(self):
        """
        Each sample's main.bicep should reference shared modules.
        This is a structural check — not a compilation check.
        Skip if files don't exist yet.
        """
        samples_dir = REPO_ROOT / "samples"
        if not samples_dir.exists():
            pytest.skip("samples/ directory not yet created")

        for sample_dir in samples_dir.iterdir():
            if not sample_dir.is_dir():
                continue
            main_bicep = sample_dir / "infra" / "main.bicep"
            if not main_bicep.exists():
                continue

            content = main_bicep.read_text(encoding="utf-8")
            # Should reference shared modules via relative path
            assert "../../infra/modules/" in content or "infra/modules/" in content, (
                f"{main_bicep.relative_to(REPO_ROOT)} does not reference shared infra modules"
            )
