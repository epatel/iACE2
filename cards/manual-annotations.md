# Manual and annotations

- The manual is `JA-Manual-Second-Edition.pdf`, bundled as `assets/manual.pdf` and viewed with `pdfrx`. PDF page 1 is an empty cover, so the original opens at page 2 by default. The last page viewed is stored in `settings.lastpage`.
- The original annotations are `archive/iACE/iACE/annotations.dic`, an NSKeyedArchiver plist mapping `{NSNumber page → NSArray<MyAnnotation{rect: CGRect, value: NSString}>}`. `tool/` converts them to `assets/annotations.json`, normalising `rect` to 0..1 of the page (the original is in 768-pt page-view space).
- Annotation `value` actions:
  - `goto N` → go to manual page `N + 2` (offset for the cover).
  - `open URL` → open an external URL.
  - `type TEXT` → spool `TEXT` into the emulator. `\` becomes a newline and a trailing newline is added. The original renders these as rounded 70×44 "type" buttons.
- There is an edit mode for authoring annotations (drag to create or move, tap to edit the value). It's only available in debug builds.
