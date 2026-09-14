# GPG Encrypted Notes

Two plugins, two workflows — pick the shape that fits how you think about
the secret.

## 1. Whole-file encryption — `gpg.nvim`

One file, one secret. Open a `*.gpg` (or `*.asc`) file and nvim
transparently decrypts it; save encrypts it back in memory. Plaintext
never touches disk, swap, undo, or ShaDa. Clipboard is disabled inside
the buffer so a yank doesn't leak decrypted text to the OS clipboard.

### Quick start

```bash
# Encrypt a fresh file — name it .gpg (or .asc) before opening
nvim chat-with-alice.asc
# type your message...
# :wq  ->  encrypted on save

# Decrypt / edit existing encrypted file
nvim chat-with-alice.asc
# you see plaintext, edit, save -> re-encrypted
```

### Session: an encrypted chat log

```bash
# Create a new encrypted conversation file
nvim alice.asc
```

```
Hi Alice,

Here's the deploy token you asked for:

tok_9f3kL7xqQ2mRpwbN8cyVj4uT

— me
```

Save — the file on disk is now a GPG-ASCII-armor blob. Re-open any time;
you get plaintext. The whole file is the conversation; each new message
you append is encrypted alongside the old ones on every save.

### Recipient targeting

Default is `--default-recipient-self` (encrypt to yourself, symmetric-ish
flow — you just unlock it with your own passphrase via gpg-agent). To
encrypt to someone else:

```lua
-- in plugins/misc.lua:
require("gpg").setup({
  default_recipient = "alice@example.com",  -- encrypt to Alice's public key
  use_armor = true,
})
```

Now `nvim alice.asc` decrypts with Alice's key + yours, and anyone else
sees only ciphertext.

### What's protected

- `noswapfile`, `noundofile`, `nobackup`, `nowritebackup` — plaintext
  never written to `~/.local/state/nvim/`.
- ShaDa cleared for the session — registers/search/marks can't capture
  decrypted snippets.
- **Not** protected: the clipboard. `allow_clipboard = true` is set
  deliberately (`plugins/misc.lua`), so `yy` inside a decrypted buffer
  puts plaintext on the OS clipboard, where any other application can
  read it and where it survives the buffer being closed. Set
  `allow_clipboard = false` if you'd rather lose the yank than take
  that.
- Failed decrypt locks the buffer (`nomodifiable`) — a wrong key can't
  overwrite your ciphertext with garbage.
- Atomic writes (`temp + rename`), file created `0600`.

### Boundaries

- Opens the file with its `.gpg`/`.asc` name *first* — protections only
  attach once the buffer is recognized. Don't `:enew`, type, then
  `:saveas secret.gpg` — the early plaintext already hit swap/ShaDa.
- Encrypts but does **not** sign; no signature verification on decrypt.
  Fine for at-rest secrecy, not for authenticity.
- Passphrase is cached by gpg-agent for the session — once per nvim
  launch you unlock, then edit freely.

---

## 2. Encrypted blocks inside Markdown — `privymd.nvim`

Many secrets, one document. Keep a normal Markdown file (passwords,
keys, private notes) and fence only the sensitive parts inside `gpg`
code blocks. Auto-decrypts on open, auto-encrypts on save. Passphrase
once per session.

### Quick start

Create `secrets.md` with front-matter naming your GPG recipient and a
fenced `gpg` block:

````markdown
---
gpg-recipient: me@example.com
---

# Project Alpha

Deploy target: `prod-db.internal:5432`

Login:
- user: admin

```gpg
password = "Sx!9vKm#2qLp$wR7"
api_key = "ak_live_4eC39HqLyjWDarjtT1zdp7dc"
```

Rotate the api_key every 90 days per policy doc.
````

Open `nvim secrets.md` → the `gpg` block renders in place as:

```
password = "Sx!9vKm#2qLp$wR7"
api_key = "ak_live_4eC39HqLyjWDarjtT1zdp7dc"
```

Save → re-encrypted. On disk the block is GPG ciphertext; in the buffer
it's plaintext.

### Multiple blocks

````markdown
---
gpg-recipient: me@example.com
---

## Work VPN

```gopenvpn
client
remote vpn.corp.example.com 1194
...
```

## Personal email backup code

```gpg
1234 5678 9012 3456
```
````

Each block is independently encrypted/decrypted. Plain markdown between
them stays readable.

### Front-matter

| Field            | Required | Meaning                                       |
| ---------------- | -------- | --------------------------------------------- |
| `gpg-recipient`  | yes      | Key id/email that can decrypt the blocks.     |

Use your own email/key → only you can open it. Use a team key → anyone
with that key can. You can change per-file by editing the front-matter.

### Commands

| Command             | What it does                                       |
| ------------------- | -------------------------------------------------- |
| `:PrivyDecrypt`     | Decrypt every `gpg` block in the current buffer.   |
| `:PrivyEncrypt`     | Re-encrypt every block (preview before saving).    |
| `:PrivyToggle`      | Toggle the block under the cursor.                 |
| `:PrivyShowBlocks`  | List all detected GPG blocks (location preview).   |
| `:PrivyClearPass`   | Drop the cached passphrase; next decrypt prompts.  |

### Boundaries

- Only text inside fenced `gpg` blocks is encrypted. Headings, lists,
  and free prose are plain Markdown — put structure outside the fence,
  secrets inside.
- Plaintext never written to disk without your explicit save.
- File can live in git — committed content is ciphertext, diffs are
  unreadable without the key.

---

## Which one?

| Shape                        | Plugin          | File    | Use case                        |
| ---------------------------- | --------------- | ------- | ------------------------------- |
| One file, fully encrypted    | `gpg.nvim`      | `*.asc` | A chat log, a private journal.  |
| Markdown, some blocks secret | `privymd.nvim`  | `*.md`  | A vault of credentials + notes. |

They coexist. A `*.asc` file uses gpg.nvim; a `*.md` file uses privymd
only when it has `gpg`-fenced blocks.
