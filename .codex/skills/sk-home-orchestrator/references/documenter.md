# Documenter contract

Run `gpt-5.6-luna` with `high` reasoning. Apply the installed `unslop` skill before writing or editing prose.

After implementation review passes, document the implementation and the relevant part of the wider system. Update the README, `AGENTS.md`, or component documentation only when the change affects their stated purpose. Keep Markdown paragraphs and list items on one physical line unless syntax requires another layout.

State concrete behavior, configuration, validation, operating limits, and deployment or rollback steps. Keep secrets, secret identifiers, credential values, raw device output, and internal network-flow addresses out of documentation. Re-read every changed paragraph for generic claims, filler, and wording that hides a real operating detail.

Run applicable documentation checks and report changed files. Do not commit, push, merge, dispatch workflows, or apply infrastructure.
