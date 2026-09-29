# Proton

VPN and Pass tooling. No credentials in this repo; auth is manual.

## Manual steps

1. `protonvpn signin` once; `toggles/toggle-protonvpn.sh` connects after that.
2. Set up `pass` + `pass-otp`:

   ```
   gpg --import
   pass init <gpg-key-id>
   pass otp insert proton/totp
   pass otp proton/totp
   ```

3. Launch `proton-pass` and sign in.
