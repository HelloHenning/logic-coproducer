# Research 8 — A10/A11 Foundation Interface Contracts

_Status: targeted implementation research — 2026-09-04_

This note records the public Logic behaviors used by the post-audit A10/A11 foundation qualification. It is deliberately narrow: the goal is to avoid inventing hidden UI contracts after the 2026-09-04 full-scope audit found missing product-critical control cases.

## A10 — stock effect insertion and chain control

Apple's Control Surfaces Support Guide documents Mackie Control **Plug-in Mixer view** as a real plug-in insertion surface:

- upper LCD row = channel strip names;
- lower LCD row = current plug-in for the active Insert slot;
- rotating a V-Pot preselects another plug-in;
- pressing that V-Pot confirms/activates the preselection and enters Plug-in Edit;
- Cursor Up/Down changes Insert slot;
- preselecting `--` fully counterclockwise and pressing the V-Pot removes the plug-in.

Source: https://support.apple.com/en-ca/guide/logicpro-css/ctls7222645e/mac

Apple also documents **Plug-in Edit view** as able to edit all automatable plug-ins, native or Audio Unit, with parameter names and values rendered on the LCD and V-Pots changing the corresponding parameters.

Source: https://support.apple.com/en-gb/guide/logicpro-css/ctls72227232/mac

### A10 architectural choice

Use the already-qualified virtual Mackie Control path for:

1. exact channel-strip LCD identity;
2. empty Insert-slot discovery;
3. stock effect preselection **without confirmation until the expected short-name token is visible**;
4. V-Pot confirmation/insertion;
5. Plug-in Edit semantic parameter name/value feedback;
6. one reversible representative parameter transaction;
7. return to Plug-in Mixer and remove the temporary instance via `--`;
8. compare the protected channel-strip plug-in fingerprint to the pre-test baseline.

AX is corroborating context only: after MCU insertion it verifies the full plug-in window identity. The test never presses an unknown plug-in candidate merely to discover what it is.

Representative mandatory native classes for the product's ordinary production/sound-recreation foundation:

- Channel EQ;
- Compressor;
- Distortion;
- ChromaVerb;
- Stereo Delay.

This is not an exhaustive Apple plug-in compatibility matrix. It samples the distinct processing families the user expects the Co-Producer to construct and control.

## A7 distinct sidechain case

Apple documents Compressor's plug-in-header **Side Chain** pop-up as the source selector for sidechain input.

Source: https://support.apple.com/guide/logicpro/use-a-side-chain-input-lgce89e66ac3/mac

The sidechain case therefore runs only while the A10 temporary Compressor exists. AX must resolve a unique Compressor window, a unique sidechain pop-up, and a unique requested source before mutation. Direct sidechain restore is attempted and read back. If that direct restore cannot be proven, the sidechain gate fails, but the runner still removes the entire disposable Compressor and requires the protected channel-strip plug-in fingerprint to return to baseline before continuing. This prevents a failed subtest from stranding a temporary effect.

## A11 — disposable track and MIDI region construction

Apple documents that importing MusicXML into an existing project creates new tracks below existing tracks with MIDI regions. If no same-named Logic track/instrument exists, Logic creates a **new software instrument track and channel strip** for the imported MusicXML part.

Source: https://support.apple.com/en-gb/guide/logicpro/lgcp67fa6594/10.7/mac/11.0

The A11 runner generates a synthetic one-part MusicXML file with a unique seven-character track name and four quarter notes. The file deliberately omits key/time-signature declarations so the construction fixture does not intentionally alter global musical-signature state.

The imported track is wholly disposable. Its creation is qualified by exact track identity plus a MIDI Event List read of the imported region.

## A11 representative region edit

Apple documents `Edit > Length > Double`: the selected region's length is doubled and its contents are repeated in the second half.

Source: https://support.apple.com/en-ca/guide/logicpro/lgcpf7c0d424/mac

The runner applies this only to the disposable imported MIDI region, rereads the region through the Event List, expects the controlled event count to double, then uses Undo and requires the original semantic Event List snapshot to return. Failure of this subtest does not endanger protected project content because the containing track remains disposable and is deleted at final cleanup.

The Event List is opened through Logic's documented `Window > Open Event List` command; Apple's default key command is Command-7, but the runner prefers semantic menu resolution rather than assuming a customized key assignment.

Source: https://support.apple.com/guide/logicpro/event-list-interface-lgcp31f1a05a/mac

## A11 stock instrument assignment

Apple's Mackie **Instrument Mixer view** documents the same safe preselection model for software instruments:

- upper LCD = channel strip names;
- lower LCD = current instrument;
- V-Pot rotation preselects;
- V-Pot press activates and enters Instrument Edit;
- `--` removes an instrument.

Source: https://support.apple.com/en-mide/guide/logicpro-css/ctls722281aa/mac

The runner searches preselection-only for Retro Synth on the disposable MusicXML track, confirms it only after the LCD token matches, and corroborates the full `Retro Synth` plug-in window identity through AX.

## Safety boundary

A10 mutates the protected `Audio 1` channel strip only after its exact baseline plug-in fingerprint is captured; each temporary effect must be removed and the fingerprint must return to baseline before the next class can run.

A11 isolates construction mutations to a disposable track. Final success or ordinary failure is only safe after the temporary track is absent and a semantic mixer-topology comparison shows the protected project returned to baseline.

Any failure to prove protected restoration stops later mutation and is reported as a foundation safety failure.
