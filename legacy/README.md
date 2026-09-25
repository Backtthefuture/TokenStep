# Legacy Python implementation

This folder holds the original Python prototype of TokenStep: a collector script
(`token_usage_monitor.py`) run by launchd, and a PyObjC menu bar app
(`TokenUsageMenuApp/`). It has been replaced by the native Swift app in
`TokenStepSwift/` and is no longer built, tested, or released.

It is kept for reference only. Paths inside it are relative to this folder, and
the icon assets it uses stay in `../TokenUsageMenuApp/assets`, which the Swift
app also bundles.
