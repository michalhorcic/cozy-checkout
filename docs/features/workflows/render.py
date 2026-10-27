#!/usr/bin/env python3
"""Render the versioned Mermaid sources with Mermaid CLI 12.0.0."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", default="mmdc", help="Path to Mermaid CLI 12.0.0")
    parser.add_argument("--browser", help="Path to an installed Chrome or Chromium")
    parser.add_argument("--no-sandbox", action="store_true", help="For isolated dev containers only")
    parser.add_argument("--only", help="Render one source by its filename stem")
    args = parser.parse_args()

    directory = Path(__file__).resolve().parent
    cli = shutil.which(args.cli)
    if cli is None:
        parser.error("Mermaid CLI not found; see docs/development/WORKFLOW_DIAGRAMS.md")
    version = subprocess.check_output([cli, "--version"], text=True).strip()
    if version != "12.0.0":
        parser.error(f"Expected Mermaid CLI 12.0.0, found {version}")

    sources = sorted(directory.glob("*.mmd"))
    if args.only:
        sources = [source for source in sources if source.stem == args.only]
    if not sources:
        parser.error("No matching Mermaid sources")

    with tempfile.TemporaryDirectory(prefix="cozy-workflow-") as temporary:
        browser_config = {}
        if args.browser:
            browser_config["executablePath"] = str(Path(args.browser).resolve())
        if args.no_sandbox:
            browser_config["args"] = ["--no-sandbox"]
        config_path = Path(temporary) / "puppeteer.json"
        config_path.write_text(json.dumps(browser_config), encoding="utf-8")

        def render(source):
            for extension in ("svg", "png"):
                subprocess.run(
                    [
                        cli, "--input", str(source),
                        "--output", str(source.with_suffix("." + extension)),
                        "--configFile", str(directory / "mermaid-config.json"),
                        "--puppeteerConfigFile", str(config_path),
                        "--svgId", "workflow-" + source.stem,
                        "--size", "1600", "--scale", "1.5",
                        "--backgroundColor", "white", "--no-font-embed", "--quiet",
                    ],
                    check=True,
                )
            print(f"Rendered {source.stem}: SVG + PNG", flush=True)

        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(render, sources))


if __name__ == "__main__":
    main()
