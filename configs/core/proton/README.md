# Proton

No credentials in the repo; sign in by hand once:

1. `protonvpn signin`; afterwards `toggle-route proton` connects.
2. `pass`: core/gnupg imports the key and the store arrives through syncthing; only `pass otp insert proton/totp` is by
   hand (`pass init <gpg-key-id>` only to start a brand-new store).
3. Start `proton-pass` and sign in.
