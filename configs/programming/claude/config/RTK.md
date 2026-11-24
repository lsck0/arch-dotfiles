# Command output

Command output here is condensed to save tokens, keeping every signal and
dropping costly noise. Treat it as the complete result, and batch related
commands into one call to avoid extra turns.

A hook rewrites a plain command into its `rtk` form, and auto mode refuses a
call whose input changed after its review, which costs a second turn. So
write the `rtk` form yourself, in every part of a chain: `rtk read <file>`
for `cat`, `head` (`--head-lines <n>`) and `tail` (`--tail-lines <n>`), and
`rtk <cmd>` for `ls`, `tree`, `find`, `grep`, `rg`, `wc`, `diff`, `jq`,
`ps`, `df`, `du`, `curl`, `systemctl`, `git`, `gh`, `make`, `cargo`, `npm`,
`uv`, `pytest`, `docker` and `kubectl`. `rtk hook check '<command>'` prints
the form of anything else, or that it is left alone.
Commands quoted in skills are written plain; run their rtk form.

Truncated results state their recovery path in their own output. Re-run a
command as `rtk bypass <cmd>` only when its result is unusable: empty when
output was clearly expected, contradicting its exit code, or garbled.
