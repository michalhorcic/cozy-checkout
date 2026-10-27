"""Navigation from existing Markdown; repository links stay useful in HTML."""

from pathlib import Path
import re
from urllib.parse import quote, unquote, urlsplit


def on_files(files, config):
    """Include all documentation, keeping the user guide before technical material."""
    groups = {
        "features": ("Návody a postupy", []),
        "integrations": ("Integrace", []),
        "development": ("Vývoj a provoz", []),
        "plans": ("Návrhy a plány", []),
    }
    home = []
    others = []
    for file in sorted(files.documentation_pages(), key=lambda item: item.src_uri):
        heading = re.search(r"^#\s+(.+)$", file.content_string, re.MULTILINE)
        title = heading.group(1) if heading else Path(file.src_uri).stem
        entry = {title: file.src_uri}
        if file.src_uri in ("README.md", "index.md"):
            home.append({"Úvod": file.src_uri})
        elif file.src_uri == "features/WORKFLOWS.md":
            home.append({"Grafické postupy": file.src_uri})
        elif file.src_uri.split("/")[0] in groups:
            groups[file.src_uri.split("/")[0]][1].append(entry)
        else:
            others.append(entry)
    config.nav = home + [{title: entries} for title, entries in groups.values() if entries] + others
    config.nav.append({"Zdrojové soubory": config.extra["source_repository"]})


def on_page_markdown(markdown, page, config, files):
    """Map links outside docs/ to GitHub without changing the original Markdown."""
    docs_root = Path(config.docs_dir).resolve()
    repo_root = docs_root.parent
    source = Path(page.file.abs_src_path)

    def replace(match):
        target = match.group(2)
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc or not parsed.path or target.startswith("/"):
            return match.group(0)
        resolved = (source.parent / unquote(parsed.path)).resolve()
        if resolved.is_dir() and resolved.is_relative_to(repo_root):
            relative = resolved.relative_to(repo_root).as_posix()
            return match.group(1) + config.extra["source_repository"].rstrip("/") + "/tree/main/" + quote(relative) + match.group(3)
        if resolved.is_relative_to(docs_root) or not resolved.is_relative_to(repo_root):
            return match.group(0)
        relative = resolved.relative_to(repo_root).as_posix()
        url = config.extra["source_repository"].rstrip("/") + "/blob/main/" + quote(relative)
        if parsed.fragment:
            url += "#" + parsed.fragment
        return match.group(1) + url + match.group(3)

    return re.sub(r"(!?\[[^\]\n]*\]\()([^\s)]+)([^)]*\))", replace, markdown)
