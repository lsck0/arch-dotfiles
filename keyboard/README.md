# Keyboard Software

## Prerequisites:

```bash
git clone --recursive https://github.com/qmk/qmk_firmware.git ~/projects/qmk_firmware
ln -sf ~/projects/arch-dotfiles/keyboard/sofle_choc ~/projects/qmk_firmware/keyboards/sofle_choc/keymaps/luca_sofle_choc
cd ~/projects/qmk_firmware/
qmk setup
```

## Building:

```bash
./build.sh
```

## Flashing:

1. disconnect the two halves
2. plug in left side
3. double click reset button
4. copy \*.uf2 onto the board
5. plug in right side
6. double click reset button
7. copy \*.uf2 onto the board
8. disconnect the board
9. connect the two halves
10. plug in left side
