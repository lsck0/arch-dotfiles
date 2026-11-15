use module.nu *

export const meta = {packages: {pacman: [helm k9s kubecolor kubectl kubectx minikube skaffold]}}

# read-only: it registers the moment a kubeconfig appears, on whatever context is current
const MCP = {type: stdio, command: npx, args: [-y "kubernetes-mcp-server@0.0.67" --read-only], env: {OTEL_SDK_DISABLED: "true"}}

export def link [cfg: record] {
    let kubeconfig = $env.KUBECONFIG? | default ($nu.home-dir | path join .kube config) | split row ":" | first
    [
        (shell-aliases kubernetes)
        (mcp-servers {kubernetes: (if ($kubeconfig | path exists) and (which npx | is-not-empty) { $MCP })})
    ]
}
