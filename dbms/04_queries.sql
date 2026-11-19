-- ============================================================================
-- AP CP3 | College Lost & Found | PostgreSQL query catalogue
-- Path in repository: dbms/04_queries.sql
-- Schema source: dbms/03_schema.sql (CP2; students, categories, item_reports,
-- report_images, possible_matches, ownership_claims, handovers).
-- ============================================================================
-- Each app operation is labelled READ (R1...) or WRITE (W1...).
-- Uses JOINs for multi-table views and the exact CP2 table/column names.
--
-- HOW TO TEST (on a FRESH database loaded with dbms/03_schema.sql):
--   psql -X -v ON_ERROR_STOP=1 -d college_lost_found_cp3 \
--        -f dbms/04_queries.sql
--
-- This is a self-contained, ROLLBACK-only demo of proposed app operations.
-- Sample emails, URLs and item descriptions are test values, NOT real users.
-- A single transaction creates dependent demo rows, queries them, then rolls
-- everything back. No application data is committed by this test script.
-- In a real app, use parameterized queries and authorize every request;
-- especially restrict distinctive_details_private and proof_description_private.
-- NEVER treat an email filter as authorization by itself.
-- ============================================================================

BEGIN;

-- WRITE W1: Register the student who lost an item.
INSERT INTO students (college_email, full_name)
VALUES ('cp3.lost@example.invalid', 'CP3 Demo Lost Student')
RETURNING student_id, college_email;

-- WRITE W2: Register the student who found an item.
INSERT INTO students (college_email, full_name)
VALUES ('cp3.found@example.invalid', 'CP3 Demo Found Student')
RETURNING student_id, college_email;

-- WRITE W3: Register the student acting as a verifier for the demo.
-- Real authorization of verifiers must be enforced by the application.
INSERT INTO students (college_email, full_name)
VALUES ('cp3.verifier@example.invalid', 'CP3 Demo Verifier')
RETURNING student_id, college_email;

-- WRITE W4: Add a category to the item catalogue.
INSERT INTO categories (category_name)
VALUES ('CP3 Demo Accessories')
RETURNING category_id, category_name;

-- WRITE W5: Submit a LOST item report (joins student and category).
INSERT INTO item_reports
    (student_id, category_id, report_type, title, description,
     distinctive_details_private, event_date, event_location)
SELECT s.student_id, c.category_id, 'LOST',
       'CP3 Demo Black Backpack', 'Black backpack lost near library',
       'Private owner-only distinguishing detail', CURRENT_DATE - 1, 'Library'
FROM students AS s
JOIN categories AS c ON c.category_name = 'CP3 Demo Accessories'
WHERE s.college_email = 'cp3.lost@example.invalid'
RETURNING report_id, report_type, status;

-- WRITE W6: Submit a FOUND item report.
INSERT INTO item_reports
    (student_id, category_id, report_type, title, description,
     event_date, event_location)
SELECT s.student_id, c.category_id, 'FOUND',
       'CP3 Demo Found Backpack', 'Backpack found at library help desk',
       CURRENT_DATE, 'Library'
FROM students AS s
JOIN categories AS c ON c.category_name = 'CP3 Demo Accessories'
WHERE s.college_email = 'cp3.found@example.invalid'
RETURNING report_id, report_type, status;

-- WRITE W7: Attach a photo URL to the FOUND report.
INSERT INTO report_images (report_id, image_url)
SELECT r.report_id, 'https://example.invalid/cp3/found-backpack.jpg'
FROM item_reports AS r
JOIN students AS s ON s.student_id = r.student_id
WHERE s.college_email = 'cp3.found@example.invalid'
  AND r.title = 'CP3 Demo Found Backpack'
  AND r.report_type = 'FOUND'
RETURNING image_id, report_id;

-- WRITE W8: Suggest a candidate match between one LOST and one FOUND report.
-- Candidate match is not proof of ownership; 0.9500 is demo input only.
INSERT INTO possible_matches (lost_report_id, found_report_id, match_score)
SELECT lost.report_id, found.report_id, 0.9500
FROM item_reports AS lost
JOIN item_reports AS found
  ON found.category_id = lost.category_id
 AND found.report_type = 'FOUND'
JOIN students AS reporter_lost ON reporter_lost.student_id = lost.student_id
JOIN students AS reporter_found ON reporter_found.student_id = found.student_id
WHERE lost.report_type = 'LOST'
  AND reporter_lost.college_email = 'cp3.lost@example.invalid'
  AND reporter_found.college_email = 'cp3.found@example.invalid'
  AND lost.title = 'CP3 Demo Black Backpack'
  AND found.title = 'CP3 Demo Found Backpack'
RETURNING lost_report_id, found_report_id, match_status;

-- WRITE W9: Change a suggested match to UNDER_REVIEW.
UPDATE possible_matches AS pm
SET match_status = 'UNDER_REVIEW'
FROM item_reports AS lost, item_reports AS found
WHERE pm.lost_report_id = lost.report_id
  AND pm.found_report_id = found.report_id
  AND lost.title = 'CP3 Demo Black Backpack'
  AND found.title = 'CP3 Demo Found Backpack'
RETURNING pm.lost_report_id, pm.found_report_id, pm.match_status;

-- WRITE W10: Submit proof of ownership for an existing candidate match.
INSERT INTO ownership_claims
    (lost_report_id, found_report_id, claimant_student_id,
     proof_description_private)
SELECT pm.lost_report_id, pm.found_report_id, claimant.student_id,
       'Private proof: unique stitched initials'
FROM possible_matches AS pm
JOIN item_reports AS lost ON lost.report_id = pm.lost_report_id
JOIN item_reports AS found ON found.report_id = pm.found_report_id
JOIN students AS claimant ON claimant.student_id = lost.student_id
WHERE claimant.college_email = 'cp3.lost@example.invalid'
  AND found.title = 'CP3 Demo Found Backpack'
RETURNING claim_id, verification_status;

-- WRITE W11: Approve a claim with a DIFFERENT verifier and timestamp.
-- The schema prevents self-verification and requires verified_at.
UPDATE ownership_claims AS oc
SET verification_status = 'APPROVED',
    verified_by_student_id = verifier.student_id,
    verified_at = CURRENT_TIMESTAMP
FROM students AS verifier
JOIN students AS claimant ON claimant.college_email = 'cp3.lost@example.invalid'
WHERE verifier.college_email = 'cp3.verifier@example.invalid'
  AND oc.claimant_student_id = claimant.student_id
  AND oc.verification_status = 'PENDING'
  AND verifier.student_id <> oc.claimant_student_id
RETURNING oc.claim_id, oc.verification_status, oc.verified_at;

-- WRITE W12: Record the item handover after verified approval.
-- The schema trigger refuses handovers for PENDING/REJECTED claims.
INSERT INTO handovers
    (claim_id, handed_over_by_student_id, received_by_student_id, notes)
SELECT oc.claim_id, finder.student_id, claimant.student_id,
       'Returned at the campus help desk'
FROM ownership_claims AS oc
JOIN item_reports AS found ON found.report_id = oc.found_report_id
JOIN students AS finder ON finder.student_id = found.student_id
JOIN students AS claimant ON claimant.student_id = oc.claimant_student_id
WHERE oc.verification_status = 'APPROVED'
  AND finder.college_email = 'cp3.found@example.invalid'
  AND claimant.college_email = 'cp3.lost@example.invalid'
RETURNING handover_id, claim_id, handed_over_at;

-- WRITE W13: Mark both reports RESOLVED only after a recorded handover.
UPDATE item_reports AS r
SET status = 'RESOLVED'
WHERE r.status IN ('OPEN', 'MATCHED')
  AND EXISTS (
      SELECT 1
      FROM ownership_claims AS oc
      JOIN handovers AS h ON h.claim_id = oc.claim_id
      WHERE r.report_id IN (oc.lost_report_id, oc.found_report_id)
  )
RETURNING r.report_id, r.report_type, r.status;

-- READ R1: Look up a student by college email (not password authentication).
SELECT s.student_id, s.full_name, s.college_email
FROM students AS s
WHERE s.college_email = 'cp3.lost@example.invalid';

-- READ R2: List item categories, including categories with no reports.
SELECT c.category_id, c.category_name, COUNT(r.report_id) AS report_count
FROM categories AS c
LEFT JOIN item_reports AS r ON r.category_id = c.category_id
GROUP BY c.category_id, c.category_name
ORDER BY c.category_name;

-- READ R3: Browse reports with their category and reporter.
-- Private distinctive_details_private is intentionally NOT exposed.
SELECT r.report_id, r.report_type, r.title, r.event_location,
       r.event_date, r.status, c.category_name, s.full_name AS reporter
FROM item_reports AS r
JOIN categories AS c ON c.category_id = r.category_id
JOIN students AS s ON s.student_id = r.student_id
WHERE r.status IN ('OPEN', 'MATCHED', 'RESOLVED')
ORDER BY r.reported_at DESC, r.report_id DESC;

-- READ R4: Search reports by item title/location and optional category.
SELECT r.report_id, r.title, r.report_type, r.event_location,
       c.category_name, r.status
FROM item_reports AS r
JOIN categories AS c ON c.category_id = r.category_id
WHERE (r.title ILIKE '%backpack%' OR r.event_location ILIKE '%library%')
  AND c.category_name = 'CP3 Demo Accessories'
ORDER BY r.event_date DESC, r.report_id DESC;

-- READ R5: Public item detail with category and reporter (no private proof).
SELECT r.report_id, r.report_type, r.title, r.description,
       r.event_date, r.event_location, r.status,
       s.full_name AS reporter, c.category_name
FROM item_reports AS r
JOIN students AS s ON s.student_id = r.student_id
JOIN categories AS c ON c.category_id = r.category_id
WHERE r.title = 'CP3 Demo Black Backpack';

-- READ R6: Show photos attached to a report.
SELECT r.report_id, r.title, img.image_id, img.image_url
FROM item_reports AS r
JOIN report_images AS img ON img.report_id = r.report_id
WHERE r.title = 'CP3 Demo Found Backpack'
ORDER BY img.image_id;

-- READ R7: Student dashboard: total LOST, FOUND and resolved reports.
SELECT s.student_id, s.full_name,
       COUNT(r.report_id) FILTER (WHERE r.report_type = 'LOST') AS lost_reports,
       COUNT(r.report_id) FILTER (WHERE r.report_type = 'FOUND') AS found_reports,
       COUNT(r.report_id) FILTER (WHERE r.status = 'RESOLVED') AS resolved_reports
FROM students AS s
LEFT JOIN item_reports AS r ON r.student_id = s.student_id
WHERE s.college_email = 'cp3.lost@example.invalid'
GROUP BY s.student_id, s.full_name;

-- READ R8: Display candidate matches with both item titles and score.
SELECT pm.lost_report_id, lost.title AS lost_item,
       pm.found_report_id, found.title AS found_item,
       pm.match_score, pm.match_status, pm.matched_at
FROM possible_matches AS pm
JOIN item_reports AS lost ON lost.report_id = pm.lost_report_id
JOIN item_reports AS found ON found.report_id = pm.found_report_id
ORDER BY pm.match_score DESC, pm.matched_at DESC;

-- READ R9: Recommended FOUND reports for a given LOST report.
SELECT found.report_id AS found_report_id, found.title,
       found.event_location, pm.match_score, pm.match_status
FROM possible_matches AS pm
JOIN item_reports AS lost ON lost.report_id = pm.lost_report_id
JOIN item_reports AS found ON found.report_id = pm.found_report_id
WHERE lost.title = 'CP3 Demo Black Backpack'
ORDER BY pm.match_score DESC, found.report_id;

-- READ R10: Verification queue: claims that still need a decision.
SELECT oc.claim_id, claimant.full_name AS claimant,
       lost.title AS lost_item, found.title AS found_item,
       oc.created_at, oc.verification_status
FROM ownership_claims AS oc
JOIN students AS claimant ON claimant.student_id = oc.claimant_student_id
JOIN item_reports AS lost ON lost.report_id = oc.lost_report_id
JOIN item_reports AS found ON found.report_id = oc.found_report_id
WHERE oc.verification_status = 'PENDING'
ORDER BY oc.created_at, oc.claim_id;

-- READ R11: Student's own claim history and review outcome.
SELECT oc.claim_id, found.title AS found_item, oc.verification_status,
       oc.created_at, oc.verified_at, verifier.full_name AS verifier
FROM ownership_claims AS oc
JOIN students AS claimant ON claimant.student_id = oc.claimant_student_id
JOIN item_reports AS found ON found.report_id = oc.found_report_id
LEFT JOIN students AS verifier ON verifier.student_id = oc.verified_by_student_id
WHERE claimant.college_email = 'cp3.lost@example.invalid'
ORDER BY oc.created_at DESC, oc.claim_id DESC;

-- READ R12: Reviewer-only evidence lookup. Application MUST authorize access.
-- WHERE on email is demonstration filtering, not an access-control check.
SELECT oc.claim_id, oc.proof_description_private, oc.verification_status,
       claimant.full_name AS claimant, verifier.full_name AS verifier
FROM ownership_claims AS oc
JOIN students AS claimant ON claimant.student_id = oc.claimant_student_id
LEFT JOIN students AS verifier ON verifier.student_id = oc.verified_by_student_id
WHERE verifier.college_email = 'cp3.verifier@example.invalid';

-- READ R13: Handover history with both participant names and item.
SELECT h.handover_id, found.title AS item,
       giver.full_name AS handed_over_by,
       receiver.full_name AS received_by,
       h.handed_over_at, h.notes
FROM handovers AS h
JOIN ownership_claims AS oc ON oc.claim_id = h.claim_id
JOIN item_reports AS found ON found.report_id = oc.found_report_id
JOIN students AS giver ON giver.student_id = h.handed_over_by_student_id
JOIN students AS receiver ON receiver.student_id = h.received_by_student_id
ORDER BY h.handed_over_at DESC, h.handover_id DESC;

-- READ R14: Status-wise counts for an admin dashboard.
SELECT r.report_type, r.status, COUNT(*) AS number_of_reports
FROM item_reports AS r
GROUP BY r.report_type, r.status
ORDER BY r.report_type, r.status;

-- READ R15: Find FOUND reports not yet handed over to an owner.
SELECT r.report_id, r.title, r.event_location, c.category_name
FROM item_reports AS r
JOIN categories AS c ON c.category_id = r.category_id
WHERE r.report_type = 'FOUND'
  AND NOT EXISTS (
      SELECT 1
      FROM ownership_claims AS oc
      JOIN handovers AS h ON h.claim_id = oc.claim_id
      WHERE oc.found_report_id = r.report_id
  )
ORDER BY r.reported_at DESC, r.report_id DESC;

-- READ R16: Per-category lost/found report statistics.
SELECT c.category_name,
       COUNT(r.report_id) FILTER (WHERE r.report_type = 'LOST') AS lost_count,
       COUNT(r.report_id) FILTER (WHERE r.report_type = 'FOUND') AS found_count,
       COUNT(r.report_id) FILTER (WHERE r.status = 'RESOLVED') AS resolved_count
FROM categories AS c
LEFT JOIN item_reports AS r ON r.category_id = c.category_id
GROUP BY c.category_id, c.category_name
ORDER BY c.category_name;

-- WRITE W14: Remove a photo from the report (example of an authorized edit).
DELETE FROM report_images AS img
USING item_reports AS r, students AS s
WHERE img.report_id = r.report_id
  AND r.student_id = s.student_id
  AND s.college_email = 'cp3.found@example.invalid'
  AND r.title = 'CP3 Demo Found Backpack'
RETURNING img.image_id, img.report_id;

-- WRITE W15: Close a resolved item report after successful return.
UPDATE item_reports AS r
SET status = 'CLOSED'
WHERE r.title = 'CP3 Demo Found Backpack'
  AND r.status = 'RESOLVED'
  AND EXISTS (
      SELECT 1 FROM ownership_claims AS oc
      JOIN handovers AS h ON h.claim_id = oc.claim_id
      WHERE oc.found_report_id = r.report_id
  )
RETURNING r.report_id, r.status;

-- WRITE W16: Update a student's display name.
UPDATE students AS s
SET full_name = 'CP3 Demo Lost Student (Updated)'
WHERE s.college_email = 'cp3.lost@example.invalid'
RETURNING s.student_id, s.full_name;

-- Roll back ALL demonstration writes; the real database remains unchanged.
ROLLBACK;
