# Command output

Command output here is condensed to save tokens, keeping every signal and
dropping costly noise. Treat it as the complete result: run commands
normally, and batch related commands into one call to avoid extra turns.
Truncated results state their recovery path in their own output. Re-run a
command as `rtk proxy <cmd>` only when its result is unusable: empty when
output was clearly expected, contradicting its exit code, or garbled.

# No recaps

Do not end a response with a recap, summary, or "what I did" section. State
results as you go, then stop. A short closing line is fine only when it carries
new information (a decision needed, a caveat, a next step), never a restatement.

# Writing in Luca's name

Before writing anything in my name, load the l-style skill and follow it. This
covers code, commits, docs, latex, math, and any message sent as me such as
gh/PR/issue comments and emails. If a task produces text or code attributed to
me, l-style applies.
