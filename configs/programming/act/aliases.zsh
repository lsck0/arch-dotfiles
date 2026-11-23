# act alone talks to rootless podman; every other docker client keeps dockerd (programming/docker)
alias act='DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock act'
