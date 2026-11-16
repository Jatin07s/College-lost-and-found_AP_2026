# CP1 · Database Normalization — College Lost & Found

**Repository:** `College-lost-and-found_AP_2026`  
**Status:** Proposed relational design based on the team's described app workflow, not an audit of existing application code.  
**Scope for CP1:** Show UNF → 1NF → 2NF → 3NF and assess BCNF where applicable.

## Problem and assumptions

A student who loses an item submits a **LOST** report. A different student who finds an item submits a **FOUND** report. The system compares type, description, approximate date and location to suggest possible pairs. A possible match **does not prove ownership**. The claiming student supplies private evidence (e.g. hidden mark, serial digits or purchase receipt); an authorized verifier checks it before approving a handover and marking the matter resolved.

- Every student has one stable `student_id` and a unique college email address.
- Each report is either LOST or FOUND, created by one student and assigned to one item category.
- A report may participate in multiple **candidate** matches; a candidate is not automatically a verified claim.
- Matching evidence/private distinguishing details should not be publicly exposed to other students.
- A verified claim can lead to at most one completed handover; status changes are controlled by the app.
- All tables and attributes below are **proposed** for AP CP2 schema implementation.

## Step 0 — Unnormalized form (UNF)

An initial all-in-one form might store:

`LostFoundRegister(report_id, reporter_name, reporter_email, category_name, item_title, report_type, location, date, matching_found_report_ids, matching_student_names, image_urls, claim_details, verification_status)`

**Problems:** list-valued `matching_found_report_ids` and `image_urls` are repeating groups; reporter and category labels are repeated across reports; match/claim/verification details become inconsistent when a row is updated. This is **not 1NF**.

## Step 1 — First Normal Form (1NF)

Make all field values atomic; use one row per report, and move repeating matches and images into separate rows.

```text
Reports_1NF(report_id PK, student_id, student_name, student_email,
            category_id, category_name, report_type, title, description,
            event_date, event_location, reported_at, status)
Matches_1NF(lost_report_id PK*, found_report_id PK*,
            lost_title, found_title, lost_student_name, found_student_name,
            score, matched_at, match_status)
ReportImages_1NF(image_id PK, report_id, image_url)
```

`*` means the *composite* primary key `(lost_report_id, found_report_id)`.

**1NF achieved:** one cell contains one value, no comma-separated report IDs or photo URLs, and each row has a key. But `student_name`/`student_email`/`category_name` still repeat, and `Matches_1NF` has partial dependencies.

## Step 2 — Second Normal Form (2NF)

2NF requires 1NF and **no non-prime attribute depending on just part of a composite candidate key**.

For `Matches_1NF`, `(lost_report_id, found_report_id)` is the key but:

- `lost_report_id → lost_title, lost_student_name`
- `found_report_id → found_title, found_student_name`
- `(lost_report_id, found_report_id) → score, matched_at, match_status`

Move lost/found item details to a keyed `ItemReports` relation and keep only attributes of the *pair* in `PossibleMatches`.

```text
ItemReports_2NF(report_id PK, student_id, student_name, student_email,
                category_id, category_name, report_type, title, description,
                event_date, event_location, reported_at, status)
PossibleMatches_2NF(lost_report_id PK*, found_report_id PK*, score,
                    matched_at, match_status)
ReportImages_2NF(image_id PK, report_id FK, image_url)
```

**2NF achieved:** the pair-dependent match attributes require the whole composite key. The single-key report table has no partial-key dependencies, but contains **transitive** dependencies.

## Step 3 — Third Normal Form (3NF)

3NF removes transitive dependencies among non-key attributes. In `ItemReports_2NF`:

- `report_id → student_id → (student_name, student_email)`
- `report_id → category_id → category_name`

Create separate `Students` and `Categories` tables; reports keep their foreign keys. Separate `OwnershipClaims` and `Handovers` to keep ownership verification and physical returns from being repeated inside report rows.

| Final proposed relation (3NF) | Columns / keys | Purpose |
|---|---|---|
| `Students` | `student_id PK`, `college_email UNIQUE`, `full_name`, `created_at` | A student is registered once |
| `Categories` | `category_id PK`, `category_name UNIQUE` | Standardized item type |
| `ItemReports` | `report_id PK`, `student_id FK`, `category_id FK`, `report_type`, `title`, `description`, `distinctive_details_private`, `event_date`, `event_location`, `reported_at`, `status` | One LOST or FOUND report per row |
| `ReportImages` | `image_id PK`, `report_id FK`, `image_url` | One image reference per row |
| `PossibleMatches` | `(lost_report_id, found_report_id) PK`, both FKs to `ItemReports`, `match_score`, `matched_at`, `match_status` | Candidate report pairs, M:N resolved by junction table |
| `OwnershipClaims` | `claim_id PK`, `lost_report_id FK`, `found_report_id FK`, `claimant_student_id FK`, `proof_description_private`, `verification_status`, `verified_by_student_id FK NULL`, `verified_at NULL`, `created_at` | Separate proof/verification record; composite FK to `PossibleMatches` in CP2 |
| `Handovers` | `handover_id PK`, `claim_id FK UNIQUE`, `handed_over_at`, `handed_over_by_student_id FK`, `received_by_student_id FK`, `notes` | Record verified physical returns |

**FDs for final 3NF design:**

| Relation | Main functional dependency / candidate key |
|---|---|
| Students | `student_id → college_email, full_name, created_at`; `college_email → student_id, full_name, created_at` |
| Categories | `category_id → category_name`; `category_name → category_id` |
| ItemReports | `report_id → student_id, category_id, report_type, title, description, distinctive_details_private, event_date, event_location, reported_at, status` |
| ReportImages | `image_id → report_id, image_url` |
| PossibleMatches | `(lost_report_id, found_report_id) → match_score, matched_at, match_status` |
| OwnershipClaims | `claim_id → lost_report_id, found_report_id, claimant_student_id, proof_description_private, verification_status, verified_by_student_id, verified_at, created_at` |
| Handovers | `handover_id → claim_id, handed_over_at, handed_over_by_student_id, received_by_student_id, notes`; `claim_id → handover_id, ...` (unique claim) |

All non-key attributes depend on a whole candidate key and not on another non-key field. A 3NF schema avoids duplicate student email/category names across thousands of reports and isolates claims from reports.

## Step 4 — Boyce–Codd Normal Form (BCNF, optional)

**BCNF rule:** for every non-trivial FD `X → Y`, `X` must be a superkey. The proposed tables satisfy BCNF **under the listed FDs and candidate-key assumptions**:

- `Students`: both `student_id` and unique `college_email` are candidate keys.
- `Categories`: both ID and unique category name are candidate keys.
- `ItemReports`, `ReportImages`, `OwnershipClaims`: their recorded determinants are PKs.
- `PossibleMatches`: `(lost_report_id, found_report_id)` is the pair key, not either ID individually.
- `Handovers`: both `handover_id` and `claim_id` are keys because `claim_id` is unique.

No non-key determinant is asserted in the proposed design; **if new business rules add one**, the BCNF analysis must be revisited. Auto-computed `match_score` should not be mistaken for proof of identity.

## Relationships and business constraints for AP CP2

- Students (1) → (N) ItemReports; Categories (1) → (N) ItemReports.
- ItemReports (LOST) ↔ ItemReports (FOUND) is M:N through PossibleMatches.
- A PossibleMatch can have multiple verification attempts, modelled as OwnershipClaims; a successful claim has at most one Handover.
- Restrict `report_type` to `LOST`/`FOUND`, prevent matching a report to itself, and enforce left side LOST / right side FOUND through application/service logic or a database trigger.
- Verification status should be `PENDING`, `APPROVED`, or `REJECTED` (proposed). Do **not** mark an item `RETURNED` until an authorized handover is recorded.
- Keep secret ownership clues/evidence access-restricted. Consider hashes for identifying serials, and use least-privilege access to personal contact information.

## Example that shows why normalization helps

If a student files three lost-item reports, the UNF/1NF table repeats their name and email three times; changing the email could require three updates. In 3NF, it is updated **once** in `Students`, and all three `ItemReports` point to the same `student_id`. A photo added later is a new `ReportImages` row; a second possible found-item match is a new `PossibleMatches` row, not a comma-separated cell.

## Conclusion

The proposed College Lost & Found data model is decomposed into 1NF, 2NF and 3NF and can satisfy BCNF under the defined FDs. It supports report submission, matching, evidence-based ownership review and documented handover **without conflating a possible match with a verified owner**. Actual table names/columns should be aligned with the app when its implementation is available.
