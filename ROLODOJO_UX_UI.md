# 🎨 ROLODOJO_UX_UI: Design Language & Interface

## 1. Visual Identity (Dojo Dark)
- **Background:** #121212 (Dojo Slate) - True black for OLED efficiency.
- **Cards:** #1E1E1E (Dojo Graphite) - Subtle elevation.
- **Accents:** #FFD700 (Sensei Gold) - Used for AI insights and "Synthesis" highlights.
- **Status:** #4CAF50 (Dojo Green) for successful saves; #F44336 (Alert Red) for security warnings.

## 2. The Card Architecture
- **Radius:** 16px rounded corners for all UI containers.
- **The "Rolo" Card:** A vertical list item representing a single event.
- **The Flip Interaction:** Tapping a fact (e.g., a phone number) "flips" the card to reveal its `last_rolo_id` and the original text that generated it.

## 3. Core Interface Components
- **The Sensei Bar:** A persistent, floating bottom-bar. It contains the text input and a "Pulse" icon showing AI activity.
- **The Stream:** A chronologically reversed feed of Rolos (Newest at bottom).
- **The Vault View:** A tabbed interface to browse URIs by category (`dojo.con`, `dojo.ent`, `dojo.med`).

## 4. Interaction Philosophy
- **Frictionless Entry:** One-tap voice or text entry from the home screen.
- **Confirmation over Correction:** When the Sensei extracts a fact, it presents a "Synthesis Card" with "Accept/Reject" buttons before updating the Attribute Vault.
- **Biometric Gate:** A blurred overlay screen that only clears upon successful FaceID/Fingerprint authentication.

