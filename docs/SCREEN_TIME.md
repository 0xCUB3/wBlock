# Screen Time

Screen Time mode is an iOS-only website policy. It uses Family Controls to shield the web domains and web categories selected in FamilyActivityPicker. Application tokens are ignored. Safari content blockers and userscripts continue to run independently.

The app stores the selection and enabled flag in `group.skula.wBlock`. It explains the permission before requesting individual Family Controls authorization. When authorization is not approved, the mode is disabled for policy purposes and existing shields are cleared; the selection is retained. The app reconciles on launch and scene activation.

The Shield Configuration extension shows wBlock and the domain or category name Apple provides. Close keeps the shield. Allow for 15 Minutes records only the received web-domain or category token and its expiry in the App Group, removes that token from the policy, and returns `.none`. The Device Activity Monitor uses one activity scheduled for the earliest expiry. Its callback prunes exceptions, reapplies the policy, and schedules the next expiry. Callbacks are delivered when the device is in use; app activation is the fallback. A failed schedule must not leave an exception active.

## Distribution requirements

Family Controls capability approval is required for the app and each of these extension App IDs and provisioning profiles:

- `skula.wBlock`
- `skula.wBlock.wBlock-Shield-Configuration`
- `skula.wBlock.wBlock-Shield-Action`
- `skula.wBlock.wBlock-Device-Activity-Monitor`

The App Store Connect capability request and review notes should describe website/category blocking, the temporary per-token allowance, and the absence of application blocking. TestFlight and App Store builds must use profiles containing Family Controls and the App Group for all four IDs.

## Testing

Use a physical iPhone or iPad for authorization, FamilyActivityPicker, shields, the secondary action, restart persistence, and Device Activity callbacks. The simulator is useful for compilation and UI layout, but it does not replace physical-device testing for Family Controls approval or monitoring behavior.
