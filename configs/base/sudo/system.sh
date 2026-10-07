#!/usr/bin/env bash

DROP_IN=/etc/sudoers.d/10-wheel

# validated first, a broken drop-in would lock every admin out; sudoers.d needs a root:root 0440 copy, not a link
visudo -cf 10-wheel
install -m440 -o root -g root 10-wheel "$DROP_IN"
