#!/usr/bin/env -S nu --no-config-file
# The bench statistics: the nearest-rank tail, a summary's verdict against its budget, and the delta to an earlier run.
use bench.nu [percentile samples-summary results-delta]
use std/assert

def main []: nothing -> nothing {
    let twenty = 1..20 | each { into float }
    assert equal ($twenty | percentile 0.95) 19.0 "p95 of 1..20 is the 19th sample"
    assert equal ([5.0 1.0 3.0] | percentile 0.95) 5.0 "p95 of three samples is the largest"
    assert equal ([7.0] | percentile 0.95) 7.0 "p95 of one sample is that sample"
    assert equal ($twenty | percentile 0.5) 10.0 "p50 of 1..20 is the 10th sample"

    let summary = $twenty | samples-summary 19
    assert equal [$summary.best_ms $summary.median_ms $summary.p95_ms $summary.max_ms $summary.runs] [1.0 10.5 19.0 20.0 20]
    assert $summary.within "p95 19 against a budget of 19 is within it"
    assert not ($twenty | samples-summary 18).within "p95 19 against a budget of 18 misses it"

    let earlier = [
        {name: a, median_ms: 100.0, p95_ms: 200.0}
        {name: b, median_ms: 50.0, p95_ms: 80.0}
        {name: a, median_ms: 1.0, p95_ms: 1.0}
    ]
    let now = [{name: a, median_ms: 110.0, p95_ms: 150.0} {name: c, median_ms: 5.0, p95_ms: 5.0}]
    let deltas = $now | results-delta $earlier
    let a = $deltas | where name == a | get 0
    assert (($a.median - 0.1 | math abs) < 1e-9) $"a's median against its newest earlier run: ($a.median)"
    assert (($a.p95 + 0.25 | math abs) < 1e-9) $"a's p95 against its newest earlier run: ($a.p95)"
    assert equal ($deltas | where name == c | get 0.median) null "a bench that never ran has no delta"
}
