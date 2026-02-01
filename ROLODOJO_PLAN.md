# 🗺️ ROLODOJO Development Roadmap

## Phase 1: The Foundation (White Belt)
- [ ] Initialize Flutter project with Clean Architecture (data, domain, presentation).
- [ ] Setup `SecurityService`: SQLCipher initialization and Flutter Secure Storage key management.
- [ ] Implement the "Rockstone" Schema: `tbl_rolos`, `tbl_records`, and `tbl_attributes`.
- [ ] Implement URI Routing: Logic to map strings to `dojo.con.*` and `dojo.ent.*` paths.
- [ ] Create the "Sensei Bar": Basic floating input field for text entry.

## Phase 2: The Scribe & The Card (Blue Belt)
- [ ] **Input Logic:** Parsing "Joe's coffee is Espresso" into an Input Rolo and updating the Attribute Vault.
- [ ] **Audit Trail:** Create the "Flip Card" UI to show the source Rolo for any given fact.
- [ ] **Soft-Delete:** Implement the `NULL` value logic for attributes to maintain history.
- [ ] **UI Aesthetics:** Apply "Dojo Dark" theme and 16px rounded card corners.

## Phase 3: The Connected Dojo (Purple Belt)
- [ ] **Gmail Sync:** Implement OAuth2 and "Dojo" label polling.
- [ ] **Telephony:** Setup Call Log monitoring and Caller ID URI matching.
- [ ] **Biometrics:** Lock the app behind FaceID/Fingerprint on every cold start.
- [ ] **Search:** Implement a "Librarian" search bar to find any URI or Attribute.

## Phase 4: Mastery & Synthesis (Black Belt)
- [ ] **Sensei Synthesis:** Logic to suggest new attributes based on existing Rolo patterns.
- [ ] **Encrypted Backup:** Export database as a `.dojo` file to Google Drive.
- [ ] **Optimization:** Synthesis of "Ghost" records to keep the local DB lightweight.
- [ ] 
