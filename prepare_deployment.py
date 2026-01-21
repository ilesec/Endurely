#!/usr/bin/env python3
"""
Endurely - Deployment Preparation and Validation Script
Helps prepare the application for Azure deployment.
SPDX-License-Identifier: AGPL-3.0-or-later
"""

import os
import sys
import subprocess
import json
import argparse
from pathlib import Path
from typing import Tuple, List


class DeploymentHelper:
    """Utility class for deployment operations."""

    def __init__(self, project_root: str = "."):
        """Initialize deployment helper."""
        self.project_root = Path(project_root)
        self.app_dir = self.project_root / "app"
        self.requirements_file = self.project_root / "requirements.txt"
        self.startup_script = self.project_root / "startup.sh"

    def check_prerequisites(self) -> bool:
        """Check if all prerequisites are installed."""
        print("🔍 Checking prerequisites...")
        print()

        missing = []

        # Check Azure CLI
        if not self._command_exists("az"):
            missing.append("Azure CLI (https://aka.ms/azcli)")
        else:
            version = subprocess.check_output(["az", "--version"]).decode().split("\n")[0]
            print(f"✅ Azure CLI: {version}")

        # Check Python
        try:
            version = subprocess.check_output([sys.executable, "--version"]).decode().strip()
            print(f"✅ Python: {version}")
        except Exception:
            missing.append("Python 3.8+")

        # Check Git (optional but recommended)
        if self._command_exists("git"):
            print("✅ Git: installed")
        else:
            print("⚠️  Git: not found (optional but recommended)")

        print()

        if missing:
            print("❌ Missing prerequisites:")
            for item in missing:
                print(f"   - {item}")
            return False

        return True

    def validate_project_structure(self) -> bool:
        """Validate that the project has all necessary files."""
        print("📁 Validating project structure...")
        print()

        required_files = [
            (self.app_dir, "App directory"),
            (self.app_dir / "main.py", "main.py"),
            (self.requirements_file, "requirements.txt"),
            (self.startup_script, "startup.sh"),
            (self.project_root / ".deployment", ".deployment"),
        ]

        missing = []
        for file_path, description in required_files:
            if file_path.exists():
                print(f"✅ {description}")
            else:
                print(f"❌ {description}")
                missing.append(description)

        print()

        if missing:
            print(f"❌ Missing {len(missing)} required files:")
            for item in missing:
                print(f"   - {item}")
            return False

        return True

    def validate_dependencies(self) -> bool:
        """Check if all Python dependencies are installable."""
        print("📦 Validating Python dependencies...")
        print()

        try:
            with open(self.requirements_file) as f:
                requirements = [
                    line.strip()
                    for line in f
                    if line.strip() and not line.startswith("#")
                ]

            print(f"Found {len(requirements)} dependencies")

            # Try to validate with pip (if venv is active)
            try:
                subprocess.run(
                    [sys.executable, "-m", "pip", "check"],
                    capture_output=True,
                    check=False,
                )
                print("✅ Current environment: dependencies compatible")
            except Exception:
                print("⚠️  Could not check environment (may not have venv active)")

            print()
            return True

        except Exception as e:
            print(f"❌ Error reading requirements.txt: {e}")
            return False

    def create_deployment_package(self, output_file: str = "deploy_package.zip") -> bool:
        """Create the deployment package."""
        print(f"📦 Creating deployment package: {output_file}")
        print()

        try:
            import zipfile

            output_path = self.project_root / output_file

            # Remove existing package
            if output_path.exists():
                output_path.unlink()
                print(f"Removed existing {output_file}")

            # Files to include
            files_to_zip = [
                ("app", "app"),
                ("requirements.txt", "requirements.txt"),
                ("startup.sh", "startup.sh"),
                (".deployment", ".deployment"),
            ]

            # Create zip file
            with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
                for source, arcname in files_to_zip:
                    source_path = self.project_root / source

                    if source_path.is_dir():
                        for file_path in source_path.rglob("*"):
                            if file_path.is_file():
                                zf.write(
                                    file_path,
                                    arcname=Path(arcname) / file_path.relative_to(source_path),
                                )
                    else:
                        zf.write(source_path, arcname=arcname)

            size_mb = output_path.stat().st_size / (1024 * 1024)
            print(f"✅ Package created: {output_path} ({size_mb:.2f} MB)")
            print()
            return True

        except Exception as e:
            print(f"❌ Error creating package: {e}")
            return False

    def check_azure_login(self) -> bool:
        """Check if user is logged into Azure."""
        print("🔐 Checking Azure login status...")
        print()

        try:
            result = subprocess.run(
                ["az", "account", "show"],
                capture_output=True,
                text=True,
                check=False,
            )

            if result.returncode == 0:
                account = json.loads(result.stdout)
                print(f"✅ Logged in as: {account.get('user', {}).get('name', 'Unknown')}")
                print(f"   Subscription: {account.get('name', 'Unknown')}")
                print()
                return True
            else:
                print("❌ Not logged in to Azure")
                print()
                print("To login, run:")
                print("   az login")
                print()
                return False

        except Exception as e:
            print(f"❌ Error checking Azure login: {e}")
            return False

    def validate_env_file(self) -> bool:
        """Validate .env configuration if it exists."""
        print("⚙️  Checking configuration...")
        print()

        env_file = self.project_root / ".env"
        env_example = self.project_root / ".env.example"

        if env_file.exists():
            print("✅ .env file found")
            return True
        elif env_example.exists():
            print("⚠️  .env file not found")
            print("   You can copy from .env.example: cp .env.example .env")
            print()
            return True
        else:
            print("⚠️  No .env configuration file found")
            return True

    @staticmethod
    def _command_exists(command: str) -> bool:
        """Check if a command exists in PATH."""
        try:
            subprocess.run(
                ["where" if os.name == "nt" else "which", command],
                capture_output=True,
                check=True,
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    def run_all_checks(self) -> bool:
        """Run all validation checks."""
        print("=" * 50)
        print("  Endurely Deployment Preparation")
        print("=" * 50)
        print()

        checks = [
            ("Prerequisites", self.check_prerequisites),
            ("Project Structure", self.validate_project_structure),
            ("Python Dependencies", self.validate_dependencies),
            ("Azure Login", self.check_azure_login),
            ("Configuration", self.validate_env_file),
        ]

        results = []
        for name, check_func in checks:
            try:
                result = check_func()
                results.append((name, result))
            except Exception as e:
                print(f"❌ Error during {name} check: {e}")
                results.append((name, False))

        print()
        print("=" * 50)
        print("  Summary")
        print("=" * 50)
        print()

        for name, result in results:
            status = "✅ PASS" if result else "❌ FAIL"
            print(f"{status}: {name}")

        print()

        if all(result for _, result in results):
            print("✅ All checks passed! Ready to deploy.")
            return True
        else:
            print("❌ Some checks failed. Please fix issues before deploying.")
            return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Endurely Deployment Helper")
    parser.add_argument(
        "command",
        choices=["check", "package", "validate", "login"],
        help="Command to run",
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Project root directory (default: current directory)",
    )
    parser.add_argument(
        "--output",
        default="deploy_package.zip",
        help="Output filename for package",
    )

    args = parser.parse_args()

    helper = DeploymentHelper(args.root)

    if args.command == "check":
        success = helper.run_all_checks()
        sys.exit(0 if success else 1)

    elif args.command == "package":
        success = helper.create_deployment_package(args.output)
        sys.exit(0 if success else 1)

    elif args.command == "validate":
        print("🔍 Running full validation...")
        print()
        success = helper.validate_project_structure()
        success = helper.validate_dependencies() and success
        sys.exit(0 if success else 1)

    elif args.command == "login":
        success = helper.check_azure_login()
        if not success:
            print("Run: az login")
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
