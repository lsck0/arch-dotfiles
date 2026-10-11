#!/usr/bin/env bash
# Interactive ROCm/HIP (python-pytorch-opt-rocm, Blender HIP, llama.cpp-hip) needs the user in the render+video
# groups to reach /dev/kfd and /dev/dri. Previously only vllm.service got them via SupplementaryGroups, so an
# interactive session had no GPU access.
[[ "$FORM_FACTOR" != wsl ]] || exit 0

group_add_admins render
group_add_admins video
