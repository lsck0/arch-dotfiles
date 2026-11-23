# base/ssh's ssh-add moved from graphical-session.target to default.target: the old wants link keeps it "enabled", so
# dot never enables it again and a login without a graphical session never loads the key. Migrations run before the
# apply, while the old [Install] is still on disk, so reenable would bring the old link back; disable drops every link
# and the apply that follows enables it under the new target.
const UNIT = "ssh-add.service"

export def up []: nothing -> nothing {
    if (^systemctl --user is-enabled --quiet $UNIT | complete).exit_code == 0 { ^systemctl --user disable $UNIT }
}
