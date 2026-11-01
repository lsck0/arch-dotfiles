# gaming/vpn-bypass's bypass moved off the shared games gid to vpn-bypass, and the old module had put every wheel
# member into games for it; those memberships go, a member someone else added stays only if not in wheel.

export const layer = "system"

const GROUP = "games"
const ADMIN_GROUP = "wheel"

def members [group: string]: nothing -> list<string> {
    open /etc/group | lines | parse "{name}:{x}:{gid}:{members}" | where name == $group | get --optional 0.members
    | default "" | split row "," | where $it != ""
}

export def up []: nothing -> nothing {
    let admins = members $ADMIN_GROUP
    members $GROUP | where $it in $admins | each {|m| ^gpasswd -d $m $GROUP | ignore } | ignore
}
