#!/usr/bin/env python3
"""Scrubs recorded fixtures so they are safe to commit.

- Replaces API-key values in URLs (api_key=, wskey=, apikey=, key=) and in
  JSON fields / headers with the literal REDACTED.
- Replaces personal home-directory paths (/Users/<name>/...) with ~/...
- Pretty-prints JSON so fixture diffs stay readable.

SalonCoreTests/FixtureHygieneTests re-checks all of this on every test run.
"""
import json
import pathlib
import re
import sys

KEY_IN_URL = re.compile(r'(?i)([?&](?:api_key|apikey|wskey|key|access_token)=)[^&"\s]+')
KEY_IN_JSON = re.compile(r'(?i)("(?:api_key|apikey|wskey|x-api-key|authorization)"\s*:\s*")[^"]*(")')
HOME_PATH = re.compile(r'/Users/[^/"\s]+')


def scrub(text: str) -> str:
    text = KEY_IN_URL.sub(r'\1REDACTED', text)
    text = KEY_IN_JSON.sub(r'\1REDACTED\2', text)
    text = HOME_PATH.sub('~', text)
    return text


def main(folder: str) -> None:
    for path in sorted(pathlib.Path(folder).glob('*.json')):
        text = scrub(path.read_text(encoding='utf-8'))
        try:
            text = json.dumps(json.loads(text), indent=2, ensure_ascii=False) + '\n'
        except json.JSONDecodeError:
            pass
        path.write_text(text, encoding='utf-8')
        print(f'scrubbed {path.name}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'SalonCoreTests/Fixtures')
