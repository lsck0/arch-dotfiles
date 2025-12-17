#!/usr/bin/env bash

set -ex

ls *.wlshm | xargs -I {} shimejictl import {}

shimejictl config set BREEDING false
