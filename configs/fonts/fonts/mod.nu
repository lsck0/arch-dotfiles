use module.nu *

export const meta = {
    packages: {
        pacman: [
            maplemono-nf noto-fonts noto-fonts-emoji noto-fonts-extra otf-atkinsonhyperlegiblemono-nerd otf-aurulent-nerd
            otf-codenewroman-nerd otf-comicshanns-nerd otf-commit-mono-nerd otf-departure-mono otf-droid-nerd
            otf-firamono-nerd
            otf-geist-mono-nerd otf-hasklig-nerd otf-hermit-nerd otf-monaspace-nerd otf-opendyslexic-nerd
            otf-overpass-nerd terminus-font-ttf ttf-0xproto-nerd ttf-3270-nerd ttf-adwaitamono-nerd ttf-agave-nerd
            ttf-annotationmono-nerd ttf-anonymous-pro ttf-anonymouspro-nerd ttf-arimo-nerd ttf-arphic-ukai
            ttf-arphic-uming ttf-atkinson-hyperlegible ttf-baekmuk ttf-bigblueterminal-nerd ttf-bitstream-vera-mono-nerd
            ttf-caladea ttf-cascadia-code ttf-cascadia-code-nerd ttf-cascadia-mono-nerd ttf-comic-mono-git
            ttf-cormorant ttf-cousine-nerd
            ttf-crimson ttf-crimson-pro ttf-crimson-pro-variable ttf-croscore ttf-d2coding-nerd ttf-daddytime-mono-nerd
            ttf-dejavu-nerd ttf-doulos-sil ttf-droid ttf-envycoder-nerd ttf-eurof ttf-fantasque-nerd
            ttf-fantasque-sans-mono ttf-fira-code ttf-fira-mono ttf-fira-sans ttf-firacode-nerd ttf-gentium
            ttf-gentium-book ttf-gentium-plus ttf-go-nerd ttf-gohu-nerd ttf-googlesanscode-nerd ttf-hack ttf-hack-nerd
            ttf-hanazono ttf-hannom ttf-heavydata-nerd ttf-iawriter-nerd ttf-ibm-plex ttf-ibmplex-mono-nerd
            ttf-inconsolata ttf-inconsolata-go-nerd ttf-inconsolata-lgc-nerd ttf-inconsolata-nerd ttf-indic-otf
            ttf-input ttf-input-nerd ttf-intone-nerd ttf-iosevka-nerd ttf-iosevkaterm-nerd ttf-iosevkatermslab-nerd
            ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-jigmo ttf-junicode ttf-junicode-variable ttf-khmer ttf-lato
            ttf-lekton-nerd ttf-liberation-mono-nerd ttf-libertinus ttf-lilex-nerd ttf-linux-libertine
            ttf-linux-libertine-g ttf-martian-mono-nerd ttf-material-icons ttf-material-symbols-variable ttf-meslo-nerd
            ttf-mona-sans ttf-monaspace-frozen ttf-monaspace-variable ttf-monocraft-git ttf-monofur ttf-monofur-nerd
            ttf-monoid ttf-monoid-nerd ttf-mononoki-nerd ttf-montserrat ttf-mplus-nerd ttf-ms-fonts
            ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono ttf-noto-nerd ttf-nunito ttf-opensans ttf-overpass
            ttf-profont-nerd ttf-proggyclean-nerd ttf-recursive-nerd ttf-roboto ttf-roboto-mono ttf-roboto-mono-nerd
            ttf-sarasa-gothic ttf-sazanami ttf-scheherazade-new ttf-sharetech-mono-nerd ttf-sourcecodepro-nerd
            ttf-space-mono-nerd ttf-terminus-nerd ttf-tibetan-machine ttf-tinos-nerd ttf-ubuntu-font-family
            ttf-ubuntu-mono-nerd ttf-ubuntu-nerd ttf-victor-mono-nerd ttf-vlgothic ttf-zed-mono-nerd
        ]
    }
}

const FONTS = [KodeMono.ttf Tektur.ttf Vollkorn.ttf Vollkorn-Italic.ttf]
# one OFL license file per vendored family (Vollkorn and Vollkorn-Italic share one)
const LICENSES = [KodeMono.OFL.txt Tektur.OFL.txt Vollkorn.OFL.txt]

export def link [cfg: record] {
    let config = (xdg config)
    let fonts = xdg data fonts
    [
        ($FONTS | each {|f| file-copy $f ($fonts | path join $f) --then [fc-cache -f $fonts] })
        ($LICENSES | each {|f| file-copy $f ($fonts | path join $f) })
        # a drop-in, not fonts.conf: plasma's font settings rewrite that one
        (file-copy fonts.conf ($config | path join fontconfig conf.d 50-dotfiles.conf))
    ]
}
