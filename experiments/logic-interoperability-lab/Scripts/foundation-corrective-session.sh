#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/foundation-corrective-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-foundation-corrective.zip"
RESULTS="${OUT}/results.txt"
PHASE="${ROOT}/.build/debug/logic-phase-a-probe"
REPAIR="${ROOT}/.build/debug/logic-foundation-repair-probe"
START_TS="$(date +%s)"
A6="NOT_RUN"; A7_NORMAL="NOT_RUN"; A7_SIDECHAIN="NOT_RUN"; A7="NOT_RUN"; A8="NOT_RUN"; A9="NOT_RUN"; A10="NOT_RUN"; A11="NOT_RUN"
A6_IMPORTED=0
A6_AUTOMATION_VIEW=0
A8_RENAMED=0
A8_MARKER="A8_REPAIR_${STAMP}"

mkdir -p "$OUT"
: > "$RESULTS"
chmod 700 "$OUT" 2>/dev/null || true
cd "$ROOT" || exit 2

record(){ printf '%s\n' "$1" | tee -a "$RESULTS"; }
package(){ rm -f "$ZIP"; (cd "$TEST_ROOT" && /usr/bin/zip -qr "$ZIP" "$(basename "$OUT")") >/dev/null 2>&1 || true; }
trap package EXIT
elapsed(){ local now delta m s; now="$(date +%s)"; delta=$((now-START_TS)); m=$((delta/60)); s=$((delta%60)); printf '%dm%02ds' "$m" "$s"; }
heartbeat(){ record "PROGRESS elapsed=$(elapsed) $1"; }
summary_get(){ python3 - "$1" "$2" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]));print(d.get(sys.argv[2],''))
except Exception:print('')
PY
}
write_summary(){ python3 - "$OUT/summary.json" "$A6" "$A7_NORMAL" "$A7_SIDECHAIN" "$A7" "$A8" "$A9" "$A10" "$A11" <<'PY'
import json,sys
p,a6,a7n,a7s,a7,a8,a9,a10,a11=sys.argv[1:]
obj={'schema':'logic-coproducer-foundation-corrective/1.0','A6':a6,'A7NormalRouting':a7n,'A7Sidechain':a7s,'A7':a7,'A8':a8,'A9':a9,'A10':a10,'A11':a11}
obj['allRequiredGatesPass']=all(obj[k]=='PASS' for k in ('A6','A7','A8','A9','A10','A11'))
json.dump(obj,open(p,'w'),indent=2,sort_keys=True)
PY
}
safety_stop(){ local gate="$1" reason="$2"; write_summary; record "RESULT=FOUNDATION_SAFETY_FAIL gate=${gate} reason=${reason}"; package; exit 30; }
run_live(){
  local label="$1" logfile="$2"; shift 2
  local rcfile="${logfile}.rc" pid rc
  rm -f "$rcfile"
  ( "$@"; printf '%s\n' "$?" > "$rcfile" ) 2>&1 | tee "$logfile" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do sleep 20; if kill -0 "$pid" 2>/dev/null; then heartbeat "active=${label}"; fi; done
  wait "$pid" 2>/dev/null || true
  rc="$(cat "$rcfile" 2>/dev/null || echo 99)"; [[ "$rc" =~ ^[0-9]+$ ]] || rc=99
  return "$rc"
}
json_rows(){ python3 - "$1" <<'PY'
import json,sys
try:print(len(json.load(open(sys.argv[1])).get('rows') or []))
except Exception:print(-1)
PY
}
resolve_logicx(){ local p="$1"; if [[ -d "$p" ]];then printf '%s\n' "$p";return 0;fi;if [[ -d "${p%.logicx}.logicx" ]];then printf '%s\n' "${p%.logicx}.logicx";return 0;fi;return 1; }
modal_clean(){
  local label="$1" out="$OUT/modal-${label}.json"
  "$REPAIR" modal-status --out "$out" > "$OUT/modal-${label}.log" 2>&1 || return 1
  python3 - "$out" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1]))
except Exception:sys.exit(2)
if d.get('saveCopyWindows'):sys.exit(3)
for w in d.get('windows') or []:
 s=str(w).lower()
 if 'save a copy as' in s:sys.exit(4)
sys.exit(0)
PY
}
track_ok(){ "$PHASE" track-context --label "$1" > "$2" 2>&1; }

record "Logic Co-Producer — evidence-driven corrective foundation session"
record "This run invalidates the prior false A9 pass and re-tests only still-unqualified A6-A11 mechanisms."
record "Safety policy: later gates never run through a leftover Save a Copy As modal; unproven protected-state restoration stops immediately."
heartbeat "overall=0% preflight"

swift build > "$OUT/build.log" 2>&1 || { record "RESULT=FOUNDATION_FAIL reason=build"; exit 20; }
"$ROOT/.build/debug/logic-lab" doctor > "$OUT/doctor.log" 2>&1 || true
if ! grep -q 'Accessibility trusted: yes' "$OUT/doctor.log" || ! grep -q 'Logic Pro running: yes' "$OUT/doctor.log"; then record "RESULT=FOUNDATION_FAIL reason=doctor-or-accessibility"; exit 20; fi
track_ok "Studio Grand" "$OUT/preflight-studio-grand.log" || { record "RESULT=FOUNDATION_FAIL reason=Studio-Grand-not-resolved"; exit 20; }
track_ok "Audio 1" "$OUT/preflight-audio-1.log" || { record "RESULT=FOUNDATION_FAIL reason=Audio-1-not-resolved"; exit 20; }
if ! modal_clean preflight; then
  "$REPAIR" dismiss-save-dialog > "$OUT/preflight-dismiss-save.log" 2>&1
  rc=$?; cat "$OUT/preflight-dismiss-save.log" | tee -a "$RESULTS"
  (( rc == 0 )) || safety_stop PREFLIGHT leftover-save-dialog-not-cleanable
  modal_clean preflight-after-dismiss || safety_stop PREFLIGHT modal-state-still-not-clean
fi

# ---------------------------------------------------------------------------
# A6 + A9 share one disposable Audio 1 region so region identity is deterministic.
# ---------------------------------------------------------------------------
heartbeat "overall~8% A6/A9 disposable audio fixture"
AUDIO="$OUT/coproducer-a6-a9-${STAMP}.wav"; AUDIO_NAME="$(basename "$AUDIO")"
python3 - "$AUDIO" <<'PY'
import math,struct,sys,wave
p=sys.argv[1];sr=44100
with wave.open(p,'wb') as w:
 w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr)
 w.writeframes(b''.join(struct.pack('<h',int(0.15*math.sin(2*math.pi*523.25*i/sr)*32767)) for i in range(sr)))
PY

"$PHASE" track-context --label "Audio 1" > "$OUT/a6-audio-track.log" 2>&1 || { A6="FAIL"; A9="FAIL"; }
"$PHASE" key --name automation-list > "$OUT/a6-open-automation-list.log" 2>&1 || true
sleep .3
"$PHASE" automation-inventory --out "$OUT/a6-baseline.json" > "$OUT/a6-baseline.log" 2>&1
base_rc=$?; base_rows=-1; (( base_rc == 0 )) && base_rows="$(json_rows "$OUT/a6-baseline.json")"
record "A6_INFO baseline_rows=${base_rows}"

"$PHASE" import-audio --track "Audio 1" --path "$AUDIO" > "$OUT/a6-a9-import.log" 2>&1
import_rc=$?; cat "$OUT/a6-a9-import.log" | tee -a "$RESULTS"
if (( import_rc == 0 )) && "$REPAIR" tracks-has --filename "$AUDIO_NAME" --present yes > "$OUT/a6-a9-tracks-has-after-import.log" 2>&1; then
  A6_IMPORTED=1
  record "FIXTURE_IMPORT=PASS track=Audio_1 filename=${AUDIO_NAME} verified_in_tracks_window=true"
else
  cat "$OUT/a6-a9-tracks-has-after-import.log" 2>/dev/null | tee -a "$RESULTS" || true
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
  A6="FAIL"; A9="FAIL"
  record "FIXTURE_IMPORT=FAIL reason=generated-region-not-independently-visible-in-Tracks"
fi

if (( A6_IMPORTED )); then
  "$PHASE" focus-main > "$OUT/a6-focus-main.log" 2>&1 || true
  "$REPAIR" select-region --track "Audio 1" --name "$AUDIO_NAME" > "$OUT/a6-select-region.log" 2>&1
  sel_rc=$?; cat "$OUT/a6-select-region.log" | tee -a "$RESULTS"
  if (( sel_rc == 0 )); then
    "$PHASE" key --name automation-toggle > "$OUT/a6-show-automation.log" 2>&1 || true; A6_AUTOMATION_VIEW=1
    "$PHASE" key --name automation-create2 > "$OUT/a6-create-points.log" 2>&1 || true
    sleep .4
    "$PHASE" automation-inventory --out "$OUT/a6-created.json" > "$OUT/a6-created.log" 2>&1
    created_rc=$?; created_rows=-1; (( created_rc == 0 )) && created_rows="$(json_rows "$OUT/a6-created.json")"
    record "A6_INFO created_rows=${created_rows}"
    if (( created_rc == 0 && created_rows > 0 )); then
      "$PHASE" automation-roundtrip --out "$OUT/a6-roundtrip.json" > "$OUT/a6-roundtrip.log" 2>&1
      rt_rc=$?; cat "$OUT/a6-roundtrip.log" | tee -a "$RESULTS"
      if (( rt_rc == 30 )); then safety_stop A6 automation-roundtrip-restoration-unproven; fi
      if (( rt_rc == 0 )); then A6="PASS"; record "A6_RESULT=PASS disposable_region=verified automation_point_roundtrip=verified"; else A6="FAIL"; record "A6_RESULT=FAIL reason=automation-roundtrip-not-qualified"; fi
      "$PHASE" automation-delete-all > "$OUT/a6-delete-automation.log" 2>&1
      del_rc=$?; cat "$OUT/a6-delete-automation.log" | tee -a "$RESULTS"
      (( del_rc == 0 )) || safety_stop A6 temporary-automation-cleanup-unproven
      "$PHASE" automation-inventory --out "$OUT/a6-final-automation.json" > "$OUT/a6-final-automation.log" 2>&1 || safety_stop A6 final-automation-inventory-unavailable
      final_rows="$(json_rows "$OUT/a6-final-automation.json")"; (( final_rows == 0 )) || safety_stop A6 final-automation-not-empty
    else
      A6="FAIL"; record "A6_RESULT=FAIL reason=region-border-automation-points-not-created baseline_rows=${base_rows}"
    fi
  else
    A6="FAIL"; record "A6_RESULT=FAIL reason=disposable-region-selection-not-qualified"
  fi

  heartbeat "overall~22% A9 strict Audio File Editor source association"
  "$PHASE" focus-main > "$OUT/a9-focus-main.log" 2>&1 || true
  "$REPAIR" select-region --track "Audio 1" --name "$AUDIO_NAME" > "$OUT/a9-select-region.log" 2>&1 || true
  "$PHASE" key --name audio-editor > "$OUT/a9-open-audio-editor.log" 2>&1 || true
  sleep .4
  "$REPAIR" source-context --filename "$AUDIO_NAME" --out "$OUT/a9-source-context-strict.json" > "$OUT/a9-source-context-strict.log" 2>&1
  source_rc=$?; cat "$OUT/a9-source-context-strict.log" | tee -a "$RESULTS"
  if (( source_rc == 0 )); then A9="PASS"; record "A9_RESULT=PASS mapping_level=1 strict_audio_file_editor_context=verified"; else A9="FAIL"; record "A9_RESULT=FAIL reason=strict-source-association-not-qualified"; fi

  # Mandatory cleanup of the disposable audio region by exact unique filename selection.
  "$PHASE" focus-main > "$OUT/a6-a9-focus-main-cleanup.log" 2>&1 || true
  "$REPAIR" select-region --track "Audio 1" --name "$AUDIO_NAME" > "$OUT/a6-a9-select-region-cleanup.log" 2>&1 || safety_stop A6-A9 disposable-region-not-reselectable-for-cleanup
  osascript -e 'tell application "System Events" to key code 51' > "$OUT/a6-a9-delete-region.log" 2>&1 || true
  sleep .35
  "$REPAIR" tracks-has --filename "$AUDIO_NAME" --present no > "$OUT/a6-a9-tracks-has-final.log" 2>&1 || safety_stop A6-A9 disposable-audio-region-still-present
  A6_IMPORTED=0
  if (( A6_AUTOMATION_VIEW )); then "$PHASE" key --name automation-toggle > "$OUT/a6-restore-automation-view.log" 2>&1 || true; A6_AUTOMATION_VIEW=0; fi
  record "A6_A9_CLEANUP=PASS disposable_audio_region_removed automation_fixture_empty"
fi

# ---------------------------------------------------------------------------
# A7 normal output routing with menu-contract probing before mutation.
# ---------------------------------------------------------------------------
heartbeat "overall~35% A7 normal routing"
"$REPAIR" output-roundtrip --track "Studio Grand" --out "$OUT/a7-output-roundtrip-repair.json" > "$OUT/a7-output-roundtrip-repair.log" 2>&1
rc=$?; cat "$OUT/a7-output-roundtrip-repair.log" | tee -a "$RESULTS"
if (( rc == 30 )); then safety_stop A7 normal-routing-restoration-unproven; fi
if (( rc == 0 )); then A7_NORMAL="PASS"; else A7_NORMAL="FAIL"; fi

# ---------------------------------------------------------------------------
# A8 modal-safe Save a Copy As + empirical track-name reconciliation.
# ---------------------------------------------------------------------------
heartbeat "overall~45% A8 modal-safe saved-copy reconciliation"
A8_BASE_REQ="$OUT/a8-baseline.logicx"; A8_CHANGED_REQ="$OUT/a8-changed.logicx"
"$REPAIR" save-copy --path "$A8_BASE_REQ" > "$OUT/a8-save-baseline-repair.log" 2>&1
base_save_rc=$?; cat "$OUT/a8-save-baseline-repair.log" | tee -a "$RESULTS"
if (( base_save_rc == 30 )); then safety_stop A8 baseline-save-dialog-restoration-unproven; fi
modal_clean after-a8-baseline || safety_stop A8 save-modal-remained-after-baseline-attempt
A8_BASE="$(resolve_logicx "$A8_BASE_REQ" 2>/dev/null || true)"
if (( base_save_rc != 0 )) || [[ -z "$A8_BASE" ]]; then A8="FAIL"; record "A8_RESULT=FAIL reason=baseline-save-copy-not-qualified modal_cleanup=verified"; fi

if [[ "$A8" == "NOT_RUN" ]]; then
  "$PHASE" rename-track --from "Studio Grand" --to "$A8_MARKER" > "$OUT/a8-rename.log" 2>&1
  if track_ok "$A8_MARKER" "$OUT/a8-marker-verify.log"; then A8_RENAMED=1; else
    if track_ok "Studio Grand" "$OUT/a8-original-after-rename-fail.log"; then A8="FAIL"; record "A8_RESULT=FAIL reason=temporary-track-rename-not-applied"; else safety_stop A8 track-name-state-ambiguous; fi
  fi
fi

if (( A8_RENAMED )); then
  "$REPAIR" save-copy --path "$A8_CHANGED_REQ" > "$OUT/a8-save-changed-repair.log" 2>&1
  changed_save_rc=$?; cat "$OUT/a8-save-changed-repair.log" | tee -a "$RESULTS"
  if (( changed_save_rc == 30 )); then
    "$PHASE" rename-track --from "$A8_MARKER" --to "Studio Grand" > "$OUT/a8-emergency-restore-name.log" 2>&1 || true
    safety_stop A8 changed-save-dialog-restoration-unproven
  fi
  modal_clean after-a8-changed || safety_stop A8 save-modal-remained-after-changed-attempt
  "$PHASE" rename-track --from "$A8_MARKER" --to "Studio Grand" > "$OUT/a8-restore-name.log" 2>&1
  restore_rc=$?; if (( restore_rc != 0 )) || ! track_ok "Studio Grand" "$OUT/a8-restored-track.log"; then safety_stop A8 live-track-name-not-restored; fi
  A8_RENAMED=0
  A8_CHANGED="$(resolve_logicx "$A8_CHANGED_REQ" 2>/dev/null || true)"
  if (( changed_save_rc != 0 )) || [[ -z "$A8_CHANGED" ]]; then A8="FAIL"; record "A8_RESULT=FAIL reason=changed-save-copy-not-qualified live_name_restore=verified"; fi
fi

if [[ "$A8" == "NOT_RUN" ]]; then
  python3 - "$A8_BASE" "$A8_CHANGED" "$A8_MARKER" "$OUT/a8-reconciliation.json" <<'PY'
import hashlib,json,os,sys
base,changed,marker,out=sys.argv[1:]
def tree_hash(root):
 h=hashlib.sha256();files=[]
 for d,_,names in os.walk(root):
  for n in sorted(names):
   p=os.path.join(d,n);rel=os.path.relpath(p,root)
   try:data=open(p,'rb').read()
   except OSError:continue
   h.update(rel.encode()+b'\0'+hashlib.sha256(data).digest());files.append((rel,len(data)))
 return h.hexdigest(),files
def counts(root,needle):
 a=needle.encode();b=needle.encode('utf-16le');raw=utf=0
 for d,_,names in os.walk(root):
  for n in names:
   try:data=open(os.path.join(d,n),'rb').read()
   except OSError:continue
   raw+=data.count(a);utf+=data.count(b)
 return raw,utf
bh0,bfiles=tree_hash(base);ch0,cfiles=tree_hash(changed);bo=counts(base,'Studio Grand');bm=counts(base,marker);cm=counts(changed,marker);bh1,_=tree_hash(base);ch1,_=tree_hash(changed)
result='PASS' if bh0==bh1 and ch0==ch1 and sum(bo)>0 and sum(bm)==0 and sum(cm)>0 else 'FAIL'
json.dump({'schema':'logic-coproducer-a8-reconciliation/1.1','result':result,'baselineHash':bh0,'changedHash':ch0,'baselineHashAfterRead':bh1,'changedHashAfterRead':ch1,'baselineOriginalCounts':bo,'baselineMarkerCounts':bm,'changedMarkerCounts':cm,'baselineFiles':len(bfiles),'changedFiles':len(cfiles),'qualifiedClaim':'empirical saved track-name reconciliation only'},open(out,'w'),indent=2,sort_keys=True)
print('RESULT='+result,'baseline_original='+str(sum(bo)),'baseline_marker='+str(sum(bm)),'changed_marker='+str(sum(cm)))
sys.exit(0 if result=='PASS' else 20)
PY
  rc=$?; cat "$OUT/a8-reconciliation.json" | tee -a "$RESULTS" >/dev/null
  if (( rc == 0 )); then A8="PASS"; record "A8_RESULT=PASS empirical_saved_track_name_reconciliation=verified parser_read_only=true"; else A8="FAIL"; record "A8_RESULT=FAIL reason=marker-not-deterministically-visible-in-saved-package parser_read_only=true"; fi
fi

# Critical modal boundary before MCU/plugin and construction gates.
modal_clean before-a10 || safety_stop A8 modal-boundary-not-clean-before-A10

# ---------------------------------------------------------------------------
# A10 + A7 true sidechain, using the existing stock-effect runner now that the
# Save dialog contamination seen in the prior evidence is explicitly blocked.
# ---------------------------------------------------------------------------
heartbeat "overall~60% A10 stock effects + A7 sidechain"
mkdir -p "$OUT/a10"
run_live "A10+A7-sidechain" "$OUT/a10-terminal.log" bash "$ROOT/Scripts/a10-stock-plugin-validation-session-v2.sh" "$OUT/a10"
rc=$?
if (( rc == 30 )); then safety_stop A10 stock-plugin-chain-restoration-unproven; fi
if [[ -f "$OUT/a10/a10-summary.json" ]]; then A10="$(summary_get "$OUT/a10/a10-summary.json" A10)"; A7_SIDECHAIN="$(summary_get "$OUT/a10/a10-summary.json" A7Sidechain)"; else A10="FAIL"; A7_SIDECHAIN="FAIL"; fi
[[ "$A7_NORMAL" == "PASS" && "$A7_SIDECHAIN" == "PASS" ]] && A7="PASS" || A7="FAIL"
record "A10_A7_RESULT A10=${A10} A7_NORMAL=${A7_NORMAL} A7_SIDECHAIN=${A7_SIDECHAIN} A7=${A7}"
modal_clean after-a10 || safety_stop A10 unexpected-save-modal-after-A10

# ---------------------------------------------------------------------------
# A11. Reuse the hardened v2 transaction/cleanup script, substituting only the
# nested-menu-aware MusicXML import command in a disposable local copy.
# ---------------------------------------------------------------------------
heartbeat "overall~85% A11 track/region/stock-instrument construction"
A11_PATCHED="$OUT/a11-construction-validation-session.patched.sh"
python3 - "$ROOT/Scripts/a11-construction-validation-session-v2.sh" "$A11_PATCHED" <<'PY'
import sys
src,dst=sys.argv[1:]
s=open(src).read()
old='"$ROOT/.build/debug/logic-foundation-probe" import-musicxml --path "$MUSICXML"'
new='"$ROOT/.build/debug/logic-foundation-repair-probe" import-musicxml --path "$MUSICXML"'
if old not in s:
 print('A11 import substitution target not found',file=sys.stderr);sys.exit(2)
open(dst,'w').write(s.replace(old,new,1))
PY
patch_rc=$?; (( patch_rc == 0 )) || { A11="FAIL"; record "A11_RESULT=FAIL reason=local-import-substitution-failed"; }
if (( patch_rc == 0 )); then
  mkdir -p "$OUT/a11"
  run_live "A11" "$OUT/a11-terminal.log" bash "$A11_PATCHED" "$OUT/a11"
  rc=$?
  if (( rc == 30 )); then safety_stop A11 disposable-construction-restoration-unproven; fi
  if [[ -f "$OUT/a11/a11-summary.json" ]]; then A11="$(summary_get "$OUT/a11/a11-summary.json" A11)"; else A11="FAIL"; fi
fi
modal_clean final || safety_stop FINAL leftover-save-modal-at-end
track_ok "Studio Grand" "$OUT/final-studio-grand.log" || safety_stop FINAL Studio-Grand-final-identity
track_ok "Audio 1" "$OUT/final-audio-1.log" || safety_stop FINAL Audio-1-final-identity

write_summary
record "FOUNDATION_GATE_SUMMARY A6=${A6} A7=${A7} A8=${A8} A9=${A9} A10=${A10} A11=${A11}"
heartbeat "overall=100% complete"
package
if [[ "$A6" == "PASS" && "$A7" == "PASS" && "$A8" == "PASS" && "$A9" == "PASS" && "$A10" == "PASS" && "$A11" == "PASS" ]]; then
  record "RESULT=FOUNDATION_PASS safety_restoration=verified"
else
  record "RESULT=FOUNDATION_SESSION_COMPLETE qualification=PARTIAL protected_project_cleanup=verified modal_cleanup=verified"
fi
printf 'Evidence ZIP: %s\n' "$ZIP"
