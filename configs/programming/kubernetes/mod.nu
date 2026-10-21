use module.nu *

export const meta = {packages: {pacman: [helm k9s kubecolor kubectl kubectx minikube skaffold]}}

const MCP = {type: stdio, command: npx, args: [-y "kubernetes-mcp-server@0.0.67"], env: {OTEL_SDK_DISABLED: "true"}}

export def link [cfg: record] {
    let kubeconfig = $env.KUBECONFIG? | default ($nu.home-dir | path join .kube config) | split row ":" | first
    json-merge ($nu.home-dir | path join .claude.json) [
        (if ($kubeconfig | path exists) { json-set [mcpServers kubernetes] $MCP } else { json-delete [mcpServers kubernetes] })
    ]
}
