# Historical reference

`launch-contracts.rs` preserves the platform-neutral, original external-process launch and controller-mapping contracts. The current application uses embedded emulation instead. This source is AGPL-3.0-only, retained for possible future external-core adapters, and is not part of the Cargo workspace or release exports.

No old repository or Git history is imported wholesale. Previous native UI, private deployment configuration and media collections are excluded. The reusable libretro boundary belongs in the active emulation crate rather than duplicated here.
