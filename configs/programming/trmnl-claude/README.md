# trmnl-claude

Claude Code usage on the TRMNL display. `trmnl-claude.nu` ports `claude_trmnl.py` from
[emaspa/trmnl-claude](https://github.com/emaspa/trmnl-claude) at `37be9a7e`, reading limits from the API's rate-limit
headers. One `poster` machine per panel.

Setup: `configs/secrets/keys/trmnl-claude.env` with `TRMNL_PLUGIN_UUID=...`; paste each `template-*.html` into the
plugin's markup editor.

```bash
./trmnl-claude.nu --dry-run   # print the payload
./trmnl-claude.nu             # post once
journalctl --user -u trmnl-claude -n 20
```
