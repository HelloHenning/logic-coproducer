# Research 6 — A5 plug-in control plane: AX / VoiceOver versus virtual MCU

_Status: completed — 2026-09-04_

## Question

Why has A5 repeatedly failed around Studio Piano even though the correct plug-in and Controls view are visibly present, and should the POC continue trying to drive plug-in parameters through macOS Accessibility or pivot to the already-qualified virtual Mackie Control / CoreMIDI path?

## Evidence from our target Mac

The repeated A5 failures have been setup / semantic-resolution failures, not failures of Studio Piano parameter mutation itself.

The latest target-Mac screenshot is especially important: Studio Piano was visibly open in **Controls** view and showed controls including Main Volume, Pedal Noise, Key Noise, Release Samples and Sympathetic Resonances, while the A5 verifier still failed to resolve a trustworthy writable semantic parameter surface. Earlier project evidence also showed several Logic-specific Accessibility irregularities: usable controls can report `AXEnabled=false`; focus can be unavailable even when Logic is active; and large Event List tables require hydration before the whole semantic state is exposed.

This makes the current problem an AX representation / inference problem rather than evidence that Logic cannot expose or edit the parameter.

## 1. What Apple actually promises for Controls view and VoiceOver

Apple's support article **“Adjust plug-ins with VoiceOver in Logic Pro for Mac and MainStage”** says that Controls view presents effect and software-instrument controls as a list for VoiceOver access, and instructs users to switch the plug-in View menu to Controls. It also documents a preference to open plug-ins in Controls view by default.

Source:
- https://support.apple.com/en-us/101781

Apple's macOS Accessibility API documentation is broader than VoiceOver. `AXUIElement` is the API used by **assistive applications / accessibility clients** to communicate with accessible applications, and `AXIsProcessTrusted()` reports whether the current process is trusted as an accessibility client. Apple does not document VoiceOver being required for a separate AX client to query the hierarchy.

Sources:
- https://developer.apple.com/documentation/applicationservices/axuielement_h
- https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted

Apple's AppKit accessibility documentation also describes accessibility relationships such as a control's `accessibilityTitleUIElement`, which is relevant to the exact class of problem we saw: a visible text label and its slider can be distinct accessibility elements whose relationship must be inferred or explicitly exposed by the app.

Source:
- https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/EnhancingtheAccessibilityofStandardAppKitControls.html

Historical Logic accessibility notes reinforce that VoiceOver can cause Logic to *offer* Controls view by default, but they do not establish that enabling VoiceOver fundamentally changes the AX hierarchy exposed to another trusted accessibility process.

Secondary source containing posts from Logic Pro product manager David Earl:
- https://www.applevis.com/comment/113780

### VoiceOver conclusion

There is **no strong evidence that turning VoiceOver on is the missing technical requirement for our external AX client**. It is plausible that Logic has VoiceOver-specific behavior in some UI paths, but the latest target-Mac evidence already showed Controls view visually active while our verifier failed. Adding a VoiceOver dependency would therefore be another experiment, not a well-supported architecture.

For A5, do not require the user to enable VoiceOver.

## 2. Apple's documented Mackie Control path is a direct match for A5

Apple explicitly documents **Mackie Control Instrument Edit view** as a way to edit instrument parameters. The key statement is that Mackie Control can edit **all instruments that can be automated**, regardless of whether they are native Logic instruments or Audio Units.

In Instrument Edit view Apple documents:

- the mode display shows `In`;
- in Name display mode, the upper LCD row contains channel-strip name, instrument name, current parameter page and total pages;
- the lower LCD row contains the parameter name mapped to each V-Pot;
- in Value display mode, the upper row contains parameter names and the lower row contains parameter values;
- rotating a V-Pot changes the corresponding instrument parameter.

Source:
- https://support.apple.com/guide/logicpro-css/instrument-edit-view-ctls722252bd/mac

Apple separately documents that the **NAME/VALUE** button switches the main LCD between parameter name and parameter value formats.

Sources:
- https://support.apple.com/en-gb/guide/logicpro-css/ctls72224fdb/mac
- https://support.apple.com/en-au/guide/logicpro-css/ctls72225094/mac

Apple documents parameter paging as part of the Mackie editor model. In Plug-in / Instrument Edit view, Cursor Left / Right shifts the current editor page by one page; with CMD/ALT it shifts by one parameter.

Source:
- https://support.apple.com/en-gb/guide/logicpro-css/ctls72224335/mac

Apple's Control Surface Group parameters expose an **Instrument Parameter Page** value which determines the parameter assigned to the leftmost encoder, with subsequent parameters assigned to subsequent encoders. This confirms that the page/encoder mapping is a first-class Logic control-surface concept rather than a visual UI trick.

Source:
- https://support.apple.com/guide/logicpro/control-surface-group-send-plug-parameters-ctls718de493/mac

Apple also documents the transition into Instrument Edit view: Instrument Mixer view shows instrument assignments across channels, and pressing the V-Pot button for a channel opens the instrument and switches to Instrument Edit view.

Source:
- https://support.apple.com/en-mide/guide/logicpro-css/ctls722281aa/mac

The equivalent Plug-in Edit path is also documented for audio/MIDI insert plug-ins and similarly supports all automatable plug-ins.

Sources:
- https://support.apple.com/en-gb/guide/logicpro-css/ctls72227232/mac
- https://support.apple.com/en-ca/guide/logicpro-css/ctls7222645e/mac

## 3. Protocol-level feasibility

Apple documents the Mackie behavior but not the complete raw MIDI implementation table. A mature open-source reverse-engineering reference for MCU documents the message forms we need:

- Instrument assignment button: note 45 (`0x2D`)
- Plug-in assignment button: note 43 (`0x2B`)
- V-Pot push 1–8: notes 32–39 (`0x20`–`0x27`)
- NAME/VALUE: note 52 (`0x34`)
- Cursor Up/Down/Left/Right: notes 96–99 (`0x60`–`0x63`)
- V-Pot rotation 1–8: CC 16–23, relative values
- host-to-device LCD text: Mackie SysEx command `0x12` with a display offset into the 112-character (2 × 56) LCD buffer

Secondary implementation reference:
- https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md

These message families are consistent with what our A4 bridge has already proven on the target Mac: the same virtual Mackie Control identity, handshake, V-Pot relative messages, button messages and Logic-to-controller feedback work bidirectionally through CoreMIDI.

Therefore the protocol risk for extending A4 into Instrument Edit is materially lower than the risk of continuing to infer Logic's plug-in parameter hierarchy through AX.

## 4. Why MCU is a better A5 control plane than AX

### AX strengths

- strong for visible semantic context;
- already useful for exact track / channel-strip identity;
- useful for opening the instrument slot and correlating Logic UI state;
- can provide independent context checks.

### AX weaknesses demonstrated in this project

- `AXEnabled` cannot be treated as a reliable identity/actionability truth for Logic controls;
- focus can be absent or counterintuitive;
- visible labels and writable controls may be separate nodes without a stable relationship;
- custom Logic views can expose partial/lazy state;
- plug-in Controls view can be visually correct while our external hierarchy still lacks a deterministic label-to-slider binding.

### MCU strengths

- Apple explicitly defines the mode for instrument parameter editing;
- Logic itself supplies instrument name, parameter page, parameter names and parameter values;
- the writable control and the displayed parameter share the same V-Pot slot by definition;
- paging is explicitly defined;
- we already qualified the virtual MCU/CoreMIDI transport and bidirectional feedback in A4;
- the mechanism also generalizes to automatable third-party Audio Units, subject to the plug-in providing meaningful parameter metadata.

### MCU limitations

- LCD names are abbreviated and require deterministic normalization;
- V-Pots are relative, so restoration must use Logic feedback rather than assuming `+1` / `-1` symmetry;
- the selected track / control-surface bank must be verified, not assumed;
- Track Lock or custom control-surface settings can change which channel follows selection;
- some third-party plug-ins expose generic `Control #N` metadata rather than useful names;
- MCU exposes automatable parameters, not every possible private GUI control.

Those limitations are measurable and fail-closed. They are preferable to guessing relationships in an undocumented custom AX hierarchy.

## 5. MIDI Device Scripts / Lua are not the immediate A5 answer

Logic supports MIDI Device Scripts (Lua) and automatic controller assignment. Apple documents those scripts primarily as a mechanism for mapping hardware controls to Smart Controls and other Logic functions.

Sources:
- https://support.apple.com/guide/logicpro/supported-control-surfaces-ctls718dd5b2/mac
- https://support.apple.com/en-mide/guide/logicpro/ctlsbfee6d57/10.7/mac/11.0

MDS may become useful later for product packaging or automatic setup, but the public documentation does not give it the same explicit dynamic **full automatable instrument parameter name/value/page** model that Apple documents for Mackie Instrument Edit. It therefore does not replace MCU for the immediate A5 proof.

## Architectural decision

Use a **hybrid control plane** for the POC:

1. **AX = semantic/context plane**
   - identify the exact `Studio Grand` fixture track/channel strip;
   - establish that the hosted native instrument is Studio Piano;
   - optionally open/correlate the plug-in UI;
   - do not require AX to map visible Controls labels onto writable plug-in parameter nodes.

2. **Virtual MCU/CoreMIDI = plug-in parameter transaction plane**
   - enter Instrument Mixer / Instrument Edit;
   - verify the target channel/instrument from Logic's MCU display;
   - page through Logic's parameter assignments;
   - select one known safe percentage-style Studio Piano parameter;
   - read its baseline from MCU value feedback;
   - perform one relative V-Pot step;
   - verify changed value from fresh Logic feedback;
   - restore to the exact baseline using fresh feedback;
   - force a new Name render and Value render and independently reverify parameter identity and baseline.

This directly tests the architectural connection A5 is meant to qualify: **can the Co-Producer identify a specific hosted instrument parameter, change it through a supported Logic control-surface mechanism, observe the result, and restore it exactly?**

## A5 runner consequence

The redesigned A5 runner must no longer block on resolving Studio Piano's writable parameter sliders through AX Controls view.

It should reuse the already-configured virtual Mackie Control from A4. No new Logic control-surface setup should be requested unless the persisted A4 binding is genuinely absent.

The first target-Mac MCU A5 run remains fail-closed:

- no parameter mutation until Studio Grand context, MCU binding, Studio Piano Instrument Edit identity, a known semantic parameter, and a readable numeric baseline are all proven;
- once mutation starts, terminal interruption is deferred until restoration is proven or the run is declared safety-critical;
- a post-mutation inability to prove the exact baseline is `A5_SAFETY_FAIL`;
- a normal A5 failure is allowed only before mutation or after verified restoration.

## Recommendation

Do **not** spend another target-Mac run on the current AX label/slider resolver and do **not** ask the user to enable VoiceOver as the next experiment.

Proceed with the MCU Instrument Edit A5 redesign. Keep the AX work as useful context evidence and as a documented limit of the Accessibility-based parameter path.