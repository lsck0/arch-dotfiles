#!/bin/env bash

set -ex

ls *.wlshm | xargs -I {} shimejictl import {}
