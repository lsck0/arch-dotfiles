# act alone talks to rootless podman; every other docker client keeps dockerd (programming/docker)
def --wrapped act [...args] { with-env {DOCKER_HOST: $"unix://($env.XDG_RUNTIME_DIR)/podman/podman.sock"} { ^act ...$args } }
