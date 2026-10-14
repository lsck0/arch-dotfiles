#!/usr/bin/env -S nu --no-config-file
# a 4000K whitepoint in the display ctm, composed with the grading preset by color-grading.py
use lib.nu [switch-run]

const GRADING = path self ../../configs/desktop/color-grading/color-grading.py

def main [action: string = "toggle"] {
    switch-run {
        label: "Night light"
        is-on: {|| (^$GRADING get nightlight | str trim) == on }
        on: {|| ^$GRADING set nightlight on }
        off: {|| ^$GRADING set nightlight off }
    } $action
}
