"""Outputs of the Pulumi stack dev, from //program:dev.

Written by rules_pulumi; do not edit. Regenerate with:

    bazel run //program:dev.outputs

Secret outputs are not in OUTPUTS: their names are in SECRET_OUTPUTS, and
their values are not in this file.
"""

_RAW = json.decode(r'''
{
  "count": 3,
  "enabled": true,
  "greeting": "hello",
  "missing": null,
  "names": ["a", "b"],
  "nested": {"path": "C:\\dir", "quote": "it's \"quoted\""},
  "token": "[secret]"
}
''')

OUTPUTS = {k: v for k, v in _RAW.items() if v != "[secret]"}

SECRET_OUTPUTS = sorted([k for k, v in _RAW.items() if v == "[secret]"])
