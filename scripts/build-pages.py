#!/usr/bin/env python3
"""Build the Pages artifact after scripts/verify-keyrings.sh succeeds."""

from html import escape
from pathlib import Path
from shutil import copyfile, rmtree
from urllib.parse import quote


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    keys_dir = root / "keys"
    output_dir = root / "_site"
    if output_dir.exists():
        rmtree(output_dir)
    output_dir.mkdir()

    entries = []
    for binary in sorted(keys_dir.glob("*.gpg")):
        links = []
        # Publish only the validated public key and its companion files.
        for extension in (".gpg", ".asc", ".fingerprint"):
            source = binary.with_suffix(extension)
            copyfile(source, output_dir / source.name)
            links.append(
                f'<a href="{escape(quote(source.name))}">{escape(source.name)}</a>'
            )
        fingerprint = binary.with_suffix(".fingerprint").read_text().strip()
        entries.append(
            f"<li><h2>{escape(binary.stem)}</h2>"
            f"<p>Fingerprint: <code>{escape(fingerprint)}</code></p>"
            f"<p>{' | '.join(links)}</p></li>"
        )

    content = "<ul>" + "\n".join(entries) + "</ul>" if entries else "<p>No public keys published yet.</p>"
    (output_dir / "index.html").write_text(
        '<!doctype html>\n<html lang="en">\n<head>\n'
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        '<title>muriyx public OpenPGP keys</title>\n</head>\n<body>\n'
        '<main><h1>muriyx public OpenPGP keys</h1>\n'
        '<p>Download a keyring (.gpg), an ASCII armored key (.asc), or its fingerprint.</p>\n'
        '<p>Confirm the fingerprint through a trusted independent channel before trusting a key.</p>\n'
        f"{content}\n</main>\n</body>\n</html>\n",
        encoding="utf-8",
    )
    print(f"Built {len(entries)} public keyring(s) in {output_dir}")


if __name__ == "__main__":
    main()
