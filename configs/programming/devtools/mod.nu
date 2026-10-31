use module.nu *

export const meta = {
    packages: {
        pacman: [
            appimagetool-git ast-grep bat bc cdecl contrast cppcheck csvi-bin expect figlet glow go-yq gonzo graphviz
            grex heh help2man hyperfine identity jless jrnl lazyjira-bin lazymake-bin ls-horizons mdbook
            mermaid-cli miller osmium-tool pastel phoronix-test-suite pipeline-gtk resvg rgx ripgrep serpl slides-git
            tesseract tesseract-data-deu tesseract-data-eng tokei vale yozefu
        ]
    }
}

export def link [cfg: record] {
    shell-aliases devtools
}
