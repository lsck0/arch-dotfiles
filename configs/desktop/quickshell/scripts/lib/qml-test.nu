# The qmltestrunner harness the shell's JS and QML tests share.

const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"

# Runs one TestCase offscreen from a temp dir that `stage` fills first with what the test imports (the JS under test,
# a module dir); the dir is also an import path. Errors with the runner's output when a case fails.
export def qml-test-run [test: string, stage: closure]: nothing -> nothing {
    let dir = mktemp --directory
    let input = $dir | path join tst_case.qml
    # remove the temp dir whether the run succeeds or a step throws
    let outcome = try {
        do $stage $dir
        $test | save $input
        with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -import $dir -input $input } | complete
    } catch {|e| {failed: $e.msg} }
    rm --recursive --force $dir
    if ($outcome | get --optional failed) != null { error make {msg: $outcome.failed} }
    if $outcome.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($outcome.stdout)($outcome.stderr)"} }
}
