#!/bin/bash
set -u

ROOT="${HOME}/logic-coproducer/experiments/logic-interoperability-lab"
TEST_ROOT="${HOME}/Desktop/logic-coproducer-tests"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${TEST_ROOT}/phase-a-completion-${STAMP}"
ZIP="${TEST_ROOT}/coproducer-phase-a-completion.zip"
RESULTS="${OUT}/results.txt"
PROBE="${ROOT}/.build/debug/logic-phase-a-probe"
A8_MARKER="A8_RECONCILE_${STAMP}"
A8_RENAMED=0
A6_TEMP_AUTOMATION=0
A9_IMPORTED=0
A6="NOT_RUN"; A7="NOT_RUN"; A8="NOT_RUN"; A9="NOT_RUN"

mkdir -p "$OUT"
: > "$RESULTS"
chmod 700 "$OUT" 2>/dev/null || true
cd "$ROOT" || exit 2

record() { printf '%s\n' "$1" | tee -a "$RESULTS"; }
bar() { local d="$1" t="$2" w=20 f=$((d*w/t)); printf '['; printf '%*s' "$f" '' | tr ' ' '█'; printf '%*s' "$((w-f))" '' | tr ' ' '░'; printf ']'; }
progress() { local s="$1" t="$2" p="$3" msg="$4"; printf '\nOverall  '; bar "$s" "$t"; printf ' %3d%%  Step %d of %d\n' "$((s*100/t))" "$s" "$t"; printf 'Current  '; bar "$p" 100; printf ' %3d%%  %s\n' "$p" "$msg"; }
package_evidence() { rm -f "$ZIP"; (cd "$TEST_ROOT" && /usr/bin/zip -qr "$ZIP" "$(basename "$OUT")") >/dev/null 2>&1 || true; }
write_summary() {
  python3 - "$OUT/summary.json" "$A6" "$A7" "$A8" "$A9" <<'PY'
import json,sys
p,a6,a7,a8,a9=sys.argv[1:]
json.dump({"schema":"logic-coproducer-phase-a-completion/1.0","A6":a6,"A7":a7,"A8":a8,"A9":a9},open(p,'w'),indent=2,sort_keys=True)
PY
}
cleanup() { write_summary 2>/dev/null || true; package_evidence; }
trap cleanup EXIT

safety_fail() {
  local gate="$1" reason="$2"
  eval "$gate=SAFETY_FAIL"
  record "RESULT=PHASE_A_SAFETY_FAIL gate=${gate} reason=${reason}"
  exit 30
}

json_rows() {
  python3 - "$1" <<'PY'
import json,sys
try: print(len(json.load(open(sys.argv[1])).get('rows') or []))
except Exception: print(-1)
PY
}

resolve_logicx() {
  local p="$1"
  if [[ -d "$p" ]]; then printf '%s\n' "$p"; return 0; fi
  if [[ -d "${p%.logicx}.logicx" ]]; then printf '%s\n' "${p%.logicx}.logicx"; return 0; fi
  return 1
}

track_ok() { "$PROBE" track-context --label "$1" > "$2" 2>&1; }

progress 1 6 10 "Build and safety preflight"
if ! swift build > "$OUT/build.log" 2>&1; then record "RESULT=PHASE_A_FAIL reason=build"; exit 20; fi
if ! "$ROOT/.build/debug/logic-lab" doctor > "$OUT/doctor.log" 2>&1 || ! grep -q 'Accessibility trusted: yes' "$OUT/doctor.log" || ! grep -q 'Logic Pro running: yes' "$OUT/doctor.log"; then
  record "RESULT=PHASE_A_FAIL reason=doctor"; cat "$OUT/doctor.log" | tee -a "$RESULTS"; exit 20
fi
if ! track_ok "Studio Grand" "$OUT/preflight-studio-grand.log" || ! track_ok "Audio 1" "$OUT/preflight-audio-1.log"; then
  record "RESULT=PHASE_A_FAIL reason=required-fixture-tracks-not-resolved"; exit 20
fi
progress 1 6 100 "Environment and fixture identity verified"

# ---------------------------------------------------------------------------
# A6 — one Automation Event List point transaction.
# ---------------------------------------------------------------------------
progress 2 6 10 "A6 Automation Event List baseline"
track_ok "Studio Grand" "$OUT/a6-track.log" || { A6="FAIL"; record "A6_RESULT=FAIL reason=studio-grand-not-resolved"; }
if [[ "$A6" == "NOT_RUN" ]]; then
  "$PROBE" key --name automation-list > "$OUT/a6-open-list.log" 2>&1 || true
  sleep 0.3
  "$PROBE" automation-inventory --out "$OUT/a6-baseline.json" > "$OUT/a6-baseline.log" 2>&1
  rc=$?
  if (( rc != 0 )); then
    A6="FAIL"; record "A6_RESULT=FAIL reason=automation-event-list-unavailable-before-mutation"
  else
    rows="$(json_rows "$OUT/a6-baseline.json")"
    record "A6_INFO=baseline_rows_${rows}"
    if (( rows == 0 )); then
      # Build a disposable fixture only from a proven empty baseline. Right Arrow is
      # Logic's default Select Next Region on Selected Track; the point command is
      # Apple's default Create 2 Automation Points at Region Borders.
      "$PROBE" track-context --label "Studio Grand" > "$OUT/a6-reselect.log" 2>&1 || true
      "$PROBE" key --name right > "$OUT/a6-select-region.log" 2>&1 || true
      "$PROBE" key --name automation-toggle > "$OUT/a6-show-automation.log" 2>&1 || true
      "$PROBE" key --name automation-create2 > "$OUT/a6-create-points.log" 2>&1 || true
      sleep 0.4
      "$PROBE" automation-inventory --out "$OUT/a6-created.json" > "$OUT/a6-created.log" 2>&1
      created_rc=$?
      created_rows=-1
      (( created_rc == 0 )) && created_rows="$(json_rows "$OUT/a6-created.json")"
      if (( created_rc != 0 || created_rows <= 0 )); then
        "$PROBE" key --name automation-toggle > "$OUT/a6-restore-view-after-no-create.log" 2>&1 || true
        A6="FAIL"; record "A6_RESULT=FAIL reason=temporary-automation-fixture-not-created protected_automation_baseline=empty"
      else
        A6_TEMP_AUTOMATION=1
        cp "$OUT/a6-created.json" "$OUT/a6-working-baseline.json"
      fi
    else
      cp "$OUT/a6-baseline.json" "$OUT/a6-working-baseline.json"
    fi
  fi
fi

if [[ "$A6" == "NOT_RUN" ]]; then
  progress 2 6 50 "A6 one point write/readback/restore"
  "$PROBE" automation-roundtrip --out "$OUT/a6-roundtrip.json" > "$OUT/a6-roundtrip.log" 2>&1
  rc=$?
  cat "$OUT/a6-roundtrip.log" | tee -a "$RESULTS"
  if (( rc == 30 )); then safety_fail A6 automation-roundtrip-restore-unproven; fi
  if (( rc != 0 )); then
    A6="FAIL"; record "A6_RESULT=FAIL reason=automation-roundtrip restoration=verified_or_no_mutation"
  else
    A6="PASS"; record "A6_RESULT=PASS transaction=one_numeric_automation_point read_write_readback=verified restoration=verified"
  fi
fi

if (( A6_TEMP_AUTOMATION )); then
  progress 2 6 80 "A6 remove disposable automation fixture"
  "$PROBE" automation-delete-all > "$OUT/a6-delete-temporary.log" 2>&1
  rc=$?
  cat "$OUT/a6-delete-temporary.log" | tee -a "$RESULTS"
  (( rc == 0 )) || safety_fail A6 temporary-automation-cleanup-unproven
  "$PROBE" automation-inventory --out "$OUT/a6-final.json" > "$OUT/a6-final.log" 2>&1 || safety_fail A6 final-automation-inventory-unavailable
  final_rows="$(json_rows "$OUT/a6-final.json")"
  (( final_rows == 0 )) || safety_fail A6 final-automation-baseline-not-empty
  "$PROBE" key --name automation-toggle > "$OUT/a6-restore-view.log" 2>&1 || true
  record "A6_CLEANUP=PASS temporary_fixture_removed exact_empty_baseline_restored"
fi
progress 2 6 100 "A6 complete"

# ---------------------------------------------------------------------------
# A7 — exact Studio Grand output edge, Stereo Out -> No Output -> Stereo Out.
# ---------------------------------------------------------------------------
progress 3 6 15 "A7 representative routing edge"
"$PROBE" output-roundtrip --track "Studio Grand" --out "$OUT/a7-output-roundtrip.json" > "$OUT/a7-output-roundtrip.log" 2>&1
rc=$?
cat "$OUT/a7-output-roundtrip.log" | tee -a "$RESULTS"
if (( rc == 30 )); then safety_fail A7 routing-restore-unproven; fi
if (( rc == 0 )); then
  A7="PASS"; record "A7_RESULT=PASS route=Studio_Grand_output changed=No_Output restored=Stereo_Out routing_fingerprint=restored"
else
  A7="FAIL"; record "A7_RESULT=FAIL reason=representative-output-edge-not-qualified protected_routing_state=unchanged_or_restored"
fi
progress 3 6 100 "A7 complete"

# ---------------------------------------------------------------------------
# A8 — Save a Copy As baseline, temporary track rename, changed copy, restore.
# ---------------------------------------------------------------------------
progress 4 6 10 "A8 saved project baseline copy"
A8_BASE_REQ="$OUT/a8-baseline.logicx"
A8_CHANGED_REQ="$OUT/a8-changed.logicx"
"$PROBE" save-copy --path "$A8_BASE_REQ" > "$OUT/a8-save-baseline.log" 2>&1
base_rc=$?
A8_BASE="$(resolve_logicx "$A8_BASE_REQ" 2>/dev/null || true)"
if (( base_rc != 0 )) || [[ -z "$A8_BASE" ]]; then
  A8="FAIL"; record "A8_RESULT=FAIL reason=baseline-save-copy-unavailable no_live_project_mutation=true"
fi

if [[ "$A8" == "NOT_RUN" ]]; then
  progress 4 6 35 "A8 temporary deterministic track rename"
  "$PROBE" rename-track --from "Studio Grand" --to "$A8_MARKER" > "$OUT/a8-rename.log" 2>&1
  rename_rc=$?
  if track_ok "$A8_MARKER" "$OUT/a8-marker-verify.log"; then
    A8_RENAMED=1
  elif track_ok "Studio Grand" "$OUT/a8-original-after-rename-failure.log"; then
    A8="FAIL"; record "A8_RESULT=FAIL reason=temporary-track-rename-not-applied protected_track_name=unchanged"
  else
    safety_fail A8 track-name-state-ambiguous-after-rename-attempt
  fi
fi

changed_rc=99
A8_CHANGED=""
if (( A8_RENAMED )); then
  progress 4 6 50 "A8 save changed copy while marker is live"
  "$PROBE" save-copy --path "$A8_CHANGED_REQ" > "$OUT/a8-save-changed.log" 2>&1
  changed_rc=$?
  A8_CHANGED="$(resolve_logicx "$A8_CHANGED_REQ" 2>/dev/null || true)"

  progress 4 6 65 "A8 restore live track name"
  "$PROBE" rename-track --from "$A8_MARKER" --to "Studio Grand" > "$OUT/a8-restore-name.log" 2>&1
  restore_rc=$?
  if (( restore_rc != 0 )) || ! track_ok "Studio Grand" "$OUT/a8-restored-track.log"; then safety_fail A8 live-track-name-not-restored; fi
  A8_RENAMED=0
  record "A8_CLEANUP=PASS live_track_name=Studio_Grand"

  if (( changed_rc != 0 )) || [[ -z "$A8_CHANGED" ]]; then
    A8="FAIL"; record "A8_RESULT=FAIL reason=changed-save-copy-unavailable restoration=verified"
  fi
fi

if [[ "$A8" == "NOT_RUN" ]]; then
  progress 4 6 80 "A8 read-only saved-copy reconciliation"
  python3 - "$A8_BASE" "$A8_CHANGED" "$A8_MARKER" "$OUT/a8-reconciliation.json" <<'PY'
import hashlib,json,os,sys
base,changed,marker,out=sys.argv[1:]

def tree_hash(root):
    h=hashlib.sha256(); files=[]
    for d,_,names in os.walk(root):
        for n in sorted(names):
            p=os.path.join(d,n); rel=os.path.relpath(p,root)
            try: data=open(p,'rb').read()
            except OSError: continue
            h.update(rel.encode()+b'\0'+hashlib.sha256(data).digest()); files.append((rel,len(data)))
    return h.hexdigest(),files

def counts(root,needle):
    a=needle.encode(); b=needle.encode('utf-16le'); raw=utf=0
    for d,_,names in os.walk(root):
        for n in names:
            p=os.path.join(d,n)
            try: data=open(p,'rb').read()
            except OSError: continue
            raw += data.count(a); utf += data.count(b)
    return raw,utf
bh0,bfiles=tree_hash(base); ch0,cfiles=tree_hash(changed)
bo=counts(base,'Studio Grand'); bm=counts(base,marker)
co=counts(changed,'Studio Grand'); cm=counts(changed,marker)
bh1,_=tree_hash(base); ch1,_=tree_hash(changed)
result='PASS' if (bh0==bh1 and ch0==ch1 and sum(bo)>0 and sum(bm)==0 and sum(cm)>0) else 'FAIL'
obj={'schema':'logic-coproducer-a8-reconciliation/1.0','result':result,'baselineHash':bh0,'changedHash':ch0,'baselineHashAfterRead':bh1,'changedHashAfterRead':ch1,'baselineOriginalCounts':bo,'baselineMarkerCounts':bm,'changedOriginalCounts':co,'changedMarkerCounts':cm,'baselineFiles':len(bfiles),'changedFiles':len(cfiles),'qualifiedClaim':'empirical saved track-name reconciliation only'}
json.dump(obj,open(out,'w'),indent=2,sort_keys=True)
print('RESULT='+result,'baseline_original='+str(sum(bo)),'baseline_marker='+str(sum(bm)),'changed_marker='+str(sum(cm)))
sys.exit(0 if result=='PASS' else 20)
PY
  rc=$?
  cat "$OUT/a8-reconciliation.json" | tee -a "$RESULTS" >/dev/null
  if (( rc == 0 )); then
    A8="PASS"; record "A8_RESULT=PASS qualified_subset=saved_track_name provenance=empirical_read_only live_restore=verified parser_writes=none"
  else
    A8="FAIL"; record "A8_RESULT=FAIL reason=saved-copy-marker-not-deterministically-reconciled live_restore=verified parser_read_only=true"
  fi
fi
progress 4 6 100 "A8 complete"

# ---------------------------------------------------------------------------
# A9 — generated audio file import, Audio File Editor association, Undo import.
# ---------------------------------------------------------------------------
progress 5 6 10 "A9 generate disposable synthetic audio source"
A9_WAV="$OUT/coproducer-a9-source-${STAMP}.wav"
python3 - "$A9_WAV" <<'PY'
import math,struct,sys,wave
p=sys.argv[1]; sr=44100
with wave.open(p,'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    frames=[]
    for i in range(sr):
        x=0.18*math.sin(2*math.pi*440*i/sr)
        frames.append(struct.pack('<h',int(max(-1,min(1,x))*32767)))
    w.writeframes(b''.join(frames))
PY
A9_NAME="$(basename "$A9_WAV")"

progress 5 6 30 "A9 import generated source on exact Audio 1 track"
"$PROBE" import-audio --track "Audio 1" --path "$A9_WAV" > "$OUT/a9-import.log" 2>&1
import_rc=$?
cat "$OUT/a9-import.log" | tee -a "$RESULTS"
if (( import_rc == 10 )); then
  A9="FAIL"; record "A9_RESULT=FAIL reason=audio-track-or-import-command-not-resolved before_mutation=true"
elif (( import_rc != 0 )); then
  safety_fail A9 import-attempt-state-unproven
else
  A9_IMPORTED=1
fi

if (( A9_IMPORTED )); then
  progress 5 6 50 "A9 open selected region in Audio File Editor"
  "$PROBE" key --name audio-editor > "$OUT/a9-open-editor.log" 2>&1 || true
  sleep 0.4
  "$PROBE" source-context --filename "$A9_NAME" --out "$OUT/a9-source-context.json" > "$OUT/a9-source-context.log" 2>&1
  source_rc=$?
  cat "$OUT/a9-source-context.log" | tee -a "$RESULTS"
  if (( source_rc == 0 )); then
    A9="PASS"
  else
    A9="FAIL"
  fi

  progress 5 6 75 "A9 undo import and prove project-region cleanup"
  "$PROBE" key --name undo > "$OUT/a9-undo-import.log" 2>&1 || safety_fail A9 undo-command-unavailable
  sleep 0.4
  "$PROBE" source-context --filename "$A9_NAME" --out "$OUT/a9-after-undo-source-context.json" > "$OUT/a9-after-undo-source-context.log" 2>&1 || true
  python3 - "$OUT/a9-after-undo-source-context.json" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(2)
# The Audio File Editor may remain open after Undo. Project cleanup requires the
# generated source to disappear from the main Tracks window; editor history is UI-only.
for title in d.get('matchingWindows') or []:
    if 'tracks' in str(title).lower(): sys.exit(3)
sys.exit(0)
PY
  cleanup_rc=$?
  (( cleanup_rc == 0 )) || safety_fail A9 imported-region-still-present-in-tracks-window
  A9_IMPORTED=0
  record "A9_CLEANUP=PASS imported_region_undone generated_source_remains_external_test_artifact_only"
  if [[ "$A9" == "PASS" ]]; then
    record "A9_RESULT=PASS mapping_level=1 associated_source_file=verified exact_source_sample_range=unproven transformed_playback_samples=unproven restoration=verified"
  else
    record "A9_RESULT=FAIL reason=selected-region-audio-file-editor-association-not-qualified restoration=verified"
  fi
fi
progress 5 6 100 "A9 complete"

# Final independent fixture identity / package.
progress 6 6 25 "Final fixture identity and safety summary"
track_ok "Studio Grand" "$OUT/final-studio-grand.log" || safety_fail FINAL studio-grand-final-identity-failed
track_ok "Audio 1" "$OUT/final-audio-1.log" || safety_fail FINAL audio-1-final-identity-failed
write_summary
record "PHASE_A_GATE_SUMMARY A6=${A6} A7=${A7} A8=${A8} A9=${A9}"
progress 6 6 75 "Package evidence"
package_evidence
progress 6 6 100 "Phase-A completion session finished"
record "RESULT=PHASE_A_COMPLETE A6=${A6} A7=${A7} A8=${A8} A9=${A9} safety_restoration=verified"
printf 'Evidence ZIP: %s\n' "$ZIP"
