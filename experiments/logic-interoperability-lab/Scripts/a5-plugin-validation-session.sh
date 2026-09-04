#!/bin/bash
set -u
ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
exec bash "$ROOT/Scripts/a5-mcu-plugin-validation-session.sh" "$@"
