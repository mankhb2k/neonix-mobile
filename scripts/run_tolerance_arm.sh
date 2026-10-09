#!/bin/bash
# Launch one scrub-tolerance A/B arm on the iPhone (Debug build already installed).
#   scripts/run_tolerance_arm.sh 0.2        # fixed 0.2 s (current default)
#   scripts/run_tolerance_arm.sh 0          # always exact
#   scripts/run_tolerance_arm.sh prop:1.5   # slack = 1.5 display frames of playhead motion, cap 0.2 s
# 8 s countdown, 60 s recording, stops by itself. Tag = tol<policy>. Phone must be unlocked.
set -euo pipefail
policy=${1:?0.2 | 0 | 0.05 | prop:1.5}
tag="tol${policy//:/-}"
xcrun devicectl device process launch --device 00008110-0006190C2EE9801E --terminate-existing \
  --environment-variables "{\"PLAYBACK_METRICS_SCENARIO\":\"T3\",\"PLAYBACK_METRICS_LEADIN\":\"8\",\"PLAYBACK_METRICS_SECONDS\":\"60\",\"PLAYBACK_METRICS_TAG\":\"$tag\",\"PLAYBACK_SCRUB_TOLERANCE\":\"$policy\"}" \
  com.neonix.editor
