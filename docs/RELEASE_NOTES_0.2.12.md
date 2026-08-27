# TokenStep 0.2.12

TokenStep 0.2.12 restores the animated Trojan Inferno flame that 0.2.11 accidentally froze, while keeping the popover-flash fix from 0.2.11.

## Fixed

- Drive the Trojan flame shader from a scene-update-driven custom uniform instead of SpriteKit's built-in time uniform, which stops advancing once a scene has been paused and resumed under an always-mounted renderer.
- The flame now keeps burning on every popover visit, including after many open/close cycles; phase stays continuous instead of resetting.
- The mounted-renderer architecture from 0.2.11 is unchanged, so the popover no longer flashes when opened.
- Add diagnostics that can log the shader clock via TOKENSTEP_ODYSSEY_MOTION_DIAGNOSTICS_PATH, plus regression coverage for the shader clock behavior.

Token totals, costs, quotas, rankings, collectors, and all other theme chapters are unchanged.
