use module.nu *

# volatile: link reads the kubeconfig, which no input hash covers wherever KUBECONFIG points
export const meta = {packages: {pacman: [helm k9s kubecolor kubectl kubectx minikube skaffold]}, volatile: true}

# read-only: it registers on the first apply after a kubeconfig appears, on whatever context is current
const MCP = {type: stdio, command: npx, args: [-y "kubernetes-mcp-server@0.1.2" --read-only], env: {OTEL_SDK_DISABLED: "true"}}

export def link [cfg: record] {
    let kubeconfig = $env.KUBECONFIG? | default ($nu.home-dir | path join .kube config) | split row ":" | first
    [
        (shell-aliases kubernetes)
        (mcp-servers {kubernetes: (if ($kubeconfig | path exists) and (which npx | is-not-empty) { $MCP })})
    ]
}
