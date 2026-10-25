export const meta = {
    packages: {
        pacman: [
            argon2 base base-devel bubblewrap coreutils curl file flatpak freetype2 gnutls jq less libappimage libev
            libgcrypt libgpg-error libjpeg-turbo libldap libpng libpqxx libpulse libva libvips libxcomposite libxinerama
            lua51-luautf8 man-db man-pages mesa ncurses openal opencl-icd-loader openssl python rustup tar tk unzip vim
            vulkan-icd-loader wget zip
        ]
    }
}

# the stable toolchain floats by design; dated and nightly ones other modules pin stay put
export def update [cfg: record]: nothing -> nothing {
    if (which rustup | is-not-empty) { ^rustup update }
}
