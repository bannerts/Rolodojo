# 🎨 ROLODOJO_UX_UI: Design Language & Interface

## 1. Visual Identity (Dojo Dark)
- **Background:** #121212 (Dojo Slate) - True black for OLED efficiency.
- **Cards:** #1E1E1E (Dojo Graphite) - Subtle elevation.
- **Accents:** #FFD700 (Sensei Gold) - Used for AI insights and "Synthesis" highlights.
- **Status:** #4CAF50 (Dojo Green) for successful saves; #F44336 (Alert Red) for security warnings.
- **Text Primary:** #FFFFFF | **Text Secondary:** #B0B0B0 | **Text Hint:** #757575
- **Border:** #2A2A2A

Defined in `lib/core/constants/dojo_theme.dart` as `DojoColors` and `DojoTheme.dark`.

## 2. The Card Architecture
- **Radius:** 16px rounded corners for all UI containers (`DojoDimens.cardRadius`).
- **The "Rolo" Card:** A vertical list item in the Stream showing type badge, summoning text, target URI, and timestamp.
- **The Flip Interaction:** `FlipCard` / `AttributeFlipCard` widget — tapping a fact "flips" the card (3D Y-axis rotation) to reveal its `last_rolo_id`, source `summoningText`, and timestamp.

## 3. Core Interface Components
- **The Sensei Bar:** A persistent bottom-bar (`SenseiBar` widget) with text input, "Pulse" icon (animated during thinking), and send button. States: `idle`, `thinking`, `synthesis`.
- **The Stream:** A chronologically reversed `ListView` of Rolo cards (newest at bottom). Tapping a card shows full details in a modal bottom sheet.
- **The Vault View:** A draggable bottom sheet listing all Records and their Attributes, with FlipCard audit trails. Accessed via the folder icon in the app bar.
- **The Search Page:** `SearchPage` with `LibrarianService` integration. Includes hint chips and result cards by type (record, attribute, rolo).
- **The Settings Page:** Backup export/import, biometric toggle, database optimization, synthesis info, and privacy policy.

## 4. Interaction Philosophy
- **Frictionless Entry:** One-tap text entry from the Sensei Bar on the home screen.
- **Confirmation over Correction:** The `SynthesisService` presents a gold-bordered "Suggestion Banner" with Accept/Reject buttons before updating the Vault.
- **Biometric Gate:** `BiometricGatePage` shows a blurred overlay that clears upon successful FaceID/Fingerprint authentication. Dev-mode skip available.

## 5. App Lifecycle Screens
- **Loading Screen:** Shows the Dojo logo and "Opening the Dojo..." during async database initialization via `FutureBuilder`.
- **Error Screen:** Displays error details if database initialization fails.
- **Success Banner:** A green bar confirming when an attribute was created/updated after a summoning.
