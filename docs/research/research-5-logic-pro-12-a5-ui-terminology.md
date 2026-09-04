# Research 5 — Logic Pro 12 A5 UI terminology and opener design

Date: 2026-09-04  
Scope: A5 native Studio Piano plug-in identity and parameter round-trip setup only.

## Conclusion

The previous A5 setup harness was looking for the right *product* name in the wrong UI layer. In Logic Pro, `Studio Grand`, `Studio Piano`, and the text shown in the occupied channel-strip Instrument slot are different identities:

- **Studio Grand** can be a track/patch name and is also an instrument choice *inside* Studio Piano.
- **Studio Piano** is the software-instrument plug-in.
- **Piano** can legitimately be the short/display name shown in the channel-strip Instrument slot.

For A5, the opener therefore must identify the Instrument slot structurally, open it, and only then canonicalize the plug-in as Studio Piano from the opened plug-in window/parameter surface. The slot label is a hint, not authoritative plug-in identity.

## 1. Tracks and channel strips are related but not the same object

Apple distinguishes tracks from channel strips. Audio and software-instrument tracks route to channel-strip objects; the Mixer and Inspector show remote-control representations of those underlying channel-strip objects. Apple explicitly says the Mixer channel strips and Inspector channel strips are remote controls for the underlying channel-strip objects.

Implications for A5:

- `Studio Grand` identifies the target **track** in the controlled fixture.
- A matching **channel strip** is the signal-processing surface associated with that track.
- The Mixer and Inspector can both expose the same target channel strip. Seeing two UI representations is not evidence of two plug-in instances.
- The opener should accept either surface and should not require the Mixer specifically.

Official Apple sources:

- Channel strips in the Environment / relationship to Mixer and Inspector: https://support.apple.com/guide/logicpro/channel-strip-objects-lgcp46edc90d/mac
- Inspector interface: https://support.apple.com/guide/logicpro/lgcpe9cc3b1d/mac
- Mixing overview: https://support.apple.com/guide/logicpro/mixing-overview-lgcpbc219818/mac
- Track selection and focused track: https://support.apple.com/guide/logicpro/lgcp66ed91bd/mac

## 2. Instrument, MIDI Effect, and Audio Effect slots are distinct components

On an instrument channel strip, Logic has a dedicated **Instrument slot** for the software instrument. This is distinct from **MIDI Effect** slots and **Audio Effect** slots. Apple uses those names consistently in the current Logic Pro for Mac guide.

For A5 this matters more than the visible text inside the slot: the target is the occupied Instrument slot on the Studio Grand channel strip, not an arbitrary plug-in-looking control whose text contains `instrument` or `Studio Piano`.

Official Apple sources:

- Channel-strip controls and Input/Instrument slot: https://support.apple.com/guide/logicpro/channel-strip-controls-lgcpbc219210/mac
- Add/remove/move/copy plug-ins: https://support.apple.com/guide/logicpro/lgcp7989b5cd/mac
- Channel-strip types: https://support.apple.com/guide/logicpro/channel-strip-types-lgcpbc2192ea/mac

## 3. Slot text is intentionally not canonical plug-in identity

Logic's Plug-in Manager supports a **Short Name**. Apple states that this short name appears in the audio-effect or instrument slot of a channel strip, and recommends at most seven characters for a narrow strip or nine for a wide strip. A custom plug-in name can also differ from the product's canonical name.

Therefore the fixture's visible `Piano` slot text is compatible with the plug-in being Studio Piano. Searching that slot for the canonical string `Studio Piano` is not a reliable identity test.

A5 rule:

- `Piano` may add confidence for this fixture.
- `Piano` must never be promoted to canonical plug-in identity.
- Canonical Studio Piano identity is established only after the plug-in is opened and its semantic parameter surface is inspected.

Official Apple source:

- Plug-in Manager, Custom Name and Short Name: https://support.apple.com/guide/logicpro/lgcp9e26ef17/mac

## 4. Opening an occupied plug-in slot

Apple documents the interaction explicitly: **click the center area of an occupied plug-in slot to open its plug-in window**. The bypass control is on the left side of the slot; plug-in replacement is a different interaction.

This maps well to the target-Mac Accessibility evidence, where an occupied instrument appeared as a plug-in-specific `AXGroup` with direct child controls whose descriptions were:

- `bypass`
- `open`
- `list`

A5 should prefer the semantic AX `open` child when it is actionable. If AX action dispatch is unavailable, a center click is an acceptable last-mile action *only after the slot has already been structurally proven to be the target Instrument slot*.

Official Apple sources:

- Work in the plug-in window: https://support.apple.com/guide/logicpro/work-in-the-plug-in-window-lgcpbc21a1fd/mac
- Add/remove/move/copy plug-ins and bypass interaction: https://support.apple.com/guide/logicpro/lgcp7989b5cd/mac

## 5. Plug-in windows, Editor view, and Controls view

Apple's plug-in window has a common header. The **View** pop-up can switch the plug-in parameter view. Apple distinguishes:

- **Editor**: the plug-in's graphical interface.
- **Controls**: a generic control representation that lists plug-in functions as horizontal sliders with numerical fields.

For A5, Controls is the useful semantic/read-write surface because the later round-trip probe needs deterministically discoverable, settable numeric parameters.

The opener should not assume that a pop-up showing `100%` is *named* `View` in AX. Instead it can identify likely View controls by their semantic text/current percentage value, open the pop-up without changing a setting, and proceed only if the resulting menu contains the exact `Controls` item.

Official Apple sources:

- Plug-in window and Editor/Controls behavior: https://support.apple.com/guide/logicpro/work-in-the-plug-in-window-lgcpbc21a1fd/mac
- VoiceOver guidance for plug-ins / Controls view: https://support.apple.com/en-us/101781

## 6. Studio Piano and Studio Grand are separate levels of identity

Apple's current Logic Pro guide defines **Studio Piano** as the sample-based software instrument. Inside Studio Piano, the Instrument pop-up offers choices including **Studio Grand**, Concert Grand, Vintage Upright, and Studio Grand (Mono Mic).

This confirms that `Studio Grand` must not be used as a synonym for the plug-in product. In the A5 fixture it can simultaneously be the track name and the currently chosen piano model inside Studio Piano.

Official Apple source:

- Studio Piano in Logic Pro for Mac: https://support.apple.com/guide/logicpro/lgcp69e6c94f/mac

## 7. Useful key commands — and why the opener should not depend on them

Apple's current default U.S. preset documents:

- `X` — Show/Hide Mixer
- `Command-2` — Open Mixer
- `V` — Show/Hide All Plug-in Windows
- `Option-K` — Open Key Command Assignments

The Inspector guide documents `I` for Show Inspector. Apple also documents an **Open/Close Instrument Plug-in of Focused Track** key command in Logic Pro 11 release notes; that command is semantically excellent for this use case.

However, Logic key commands are user-configurable, and Apple's default-key table is explicitly for the default U.S. preset. The release notes establish that the focused-track instrument command exists, not that a particular keyboard chord is universally assigned to it.

A5 rule:

- Do not synthesize `X`, `V`, or an assumed shortcut for the focused-track instrument command as a primary automation route.
- Prefer AX menu items/control-bar controls and the Instrument slot's semantic `open` action.
- The focused-track instrument command remains a promising future route if its current assignment can be read without changing user settings.

Official Apple sources:

- Global key commands: https://support.apple.com/guide/logicpro/global-commands-lgcp02bf31b6/mac
- Key commands overview: https://support.apple.com/guide/logicpro/key-commands-overview-lgcp32e85cd9/mac
- Logic Pro 11 release notes mentioning `Open/Close Instrument Plug-in of Focused Track`: https://support.apple.com/en-us/126835

## 8. Comparison with target-Mac AX evidence

Existing target-Mac evidence already contains the structural pattern needed for a reliable opener. In the same channel-strip branch, the AX children appeared in this order:

1. `audio plug-in` button
2. occupied instrument group (`E-Piano` in that earlier capture)
   - `bypass`
   - `open`
   - `list`
3. `MIDI plug-in` button

The same occupied group and children were reported `enabled=false` in that capture. That is important: **AXEnabled is not safe as an identity/discovery filter for the slot**. It can still be considered when choosing an action, but a structurally valid occupied slot must not disappear from discovery merely because another Logic area has focus.

The previous A5 opener contradicted this evidence in three ways:

1. It searched slot text for `Studio Piano`, `software instrument`, or `instrument slot`.
2. It required candidate slot controls to be enabled during discovery.
3. It inferred target selection from any selected descendant of the channel strip.

All three conditions are now removed from the identity path.

## 9. Redesigned A5 opener

The implementation in `Sources/LogicA5AutoSetup/main.swift` now follows this order:

1. Activate Logic and find every minimal channel-strip UI container that contains the exact fixture track name plus channel-strip volume/pan controls.
2. Accept either Mixer or Inspector representation; do not require a single UI surface.
3. If no target strip is visible, open Inspector or Mixer through semantic control-bar/menu actions rather than raw customizable key presses.
4. Within target-strip descendants, identify occupied slot groups by the direct-child signature `bypass + open + list`.
5. Classify the Instrument slot using the surrounding `audio plug-in` and `MIDI plug-in` component markers; use visible `Piano` only as a fixture display hint.
6. Do not require AXEnabled for slot identity.
7. Open the slot with the semantic `open` child when possible; otherwise use Apple's documented center-click interaction after structural qualification.
8. After the plug-in window appears, establish Studio Piano identity from canonical window content and/or several Studio-Piano-specific semantic parameters.
9. If no settable numeric semantic parameters are exposed, locate the View pop-up non-destructively and choose `Controls` only after verifying that the opened menu contains that exact item.
10. Only after those checks return PASS does the existing A5 session runner proceed to the one-parameter read/write/readback/restore test.

This remains fail-closed: inability to resolve a structurally qualified Instrument slot, canonicalize the plug-in window, reach Controls, or expose a unique numeric semantic parameter aborts before the A5 parameter mutation.

## 10. A6–A9 workflow consequence

No change to the agreed workflow: once A5 passes, A6–A9 should be exercised as one unattended Phase-A batch with independent gate results, automatic restoration, continued execution after ordinary gate failures, and one evidence bundle rather than repeated short user-driven setup tests.
