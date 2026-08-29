from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_suffix(".m")


class RelativeGeometryTests(unittest.TestCase):
    def test_objective_c_geometry_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            binary = Path(temp_dir) / "relative-geometry-tests"
            subprocess.run(
                [
                    "xcrun",
                    "clang",
                    "-fobjc-arc",
                    "-framework",
                    "Foundation",
                    "-framework",
                    "CoreGraphics",
                    str(FIXTURE),
                    "-o",
                    str(binary),
                ],
                cwd=REPO_ROOT,
                check=True,
            )
            subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()
