# AP CP4 — Query Execution Timings

## Methodology

- Database: PostgreSQL 16.
- Source: `dbms/04_queries.sql`.
- Method: `EXPLAIN (ANALYZE, BUFFERS)`.
- Every query measured 3 times.
- Average = mean of the three execution times.
- Demo writes execute inside BEGIN/ROLLBACK.
- Raw plans saved under `dbms/plans/`.

## Timing Results

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|---|---|---|---:|---:|---:|---:|---|
| R1 | READ | Look up a student by college email (not password authentication). | 0.009 | 0.007 | 0.005 | 0.007 | Index Scan |
| R2 | READ | List item categories, including categories with no reports. | 0.071 | 0.040 | 0.028 | 0.046 | Seq Scan |
| R3 | READ | Browse reports with their category and reporter. | 0.068 | 0.040 | 0.025 | 0.044 | Seq Scan |
| R4 | READ | Search reports by item title/location and optional category. | 0.039 | 0.022 | 0.015 | 0.025 | Seq Scan, Index Scan |
| R5 | READ | Public item detail with category and reporter (no private proof). | 0.021 | 0.015 | 0.009 | 0.015 | Seq Scan, Index Scan |
| R6 | READ | Show photos attached to a report. | 0.020 | 0.014 | 0.008 | 0.014 | Seq Scan |
| R7 | READ | Student dashboard: total LOST, FOUND and resolved reports. | 0.046 | 0.027 | 0.016 | 0.030 | Seq Scan, Index Scan |
| R8 | READ | Display candidate matches with both item titles and score. | 0.037 | 0.024 | 0.014 | 0.025 | Seq Scan |
| R9 | READ | Recommended FOUND reports for a given LOST report. | 0.029 | 0.019 | 0.012 | 0.020 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |
| R10 | READ | Verification queue: claims that still need a decision. | 0.024 | 0.020 | 0.011 | 0.018 | Seq Scan, Index Scan |
| R11 | READ | Student's own claim history and review outcome. | 0.028 | 0.024 | 0.013 | 0.022 | Seq Scan, Index Scan |
| R12 | READ | Reviewer-only evidence lookup. Application MUST authorize access. | 0.021 | 0.036 | 0.020 | 0.026 | Seq Scan, Index Scan |
| R13 | READ | Handover history with both participant names and item. | 0.058 | 0.038 | 0.030 | 0.042 | Seq Scan |
| R14 | READ | Status-wise counts for an admin dashboard. | 0.023 | 0.013 | 0.010 | 0.015 | Seq Scan |
| R15 | READ | Find FOUND reports not yet handed over to an owner. | 0.032 | 0.017 | 0.015 | 0.021 | Seq Scan, Index Scan |
| R16 | READ | Per-category lost/found report statistics. | 0.032 | 0.018 | 0.016 | 0.022 | Seq Scan |
| W1 | WRITE | Register the student who lost an item. | 0.477 | 0.334 | 0.277 | 0.363 | No scan node |
| W2 | WRITE | Register the student who found an item. | 0.047 | 0.027 | 0.022 | 0.032 | No scan node |
| W3 | WRITE | Register the student acting as a verifier for the demo. | 0.038 | 0.021 | 0.028 | 0.029 | No scan node |
| W4 | WRITE | Add a category to the item catalogue. | 0.126 | 0.122 | 0.100 | 0.116 | No scan node |
| W5 | WRITE | Submit a LOST item report (joins student and category). | 0.530 | 0.492 | 0.405 | 0.476 | Index Scan |
| W6 | WRITE | Submit a FOUND item report. | 0.079 | 0.110 | 0.088 | 0.092 | Index Scan |
| W7 | WRITE | Attach a photo URL to the FOUND report. | 0.159 | 0.192 | 0.129 | 0.160 | Seq Scan, Index Scan |
| W8 | WRITE | Suggest a candidate match between one LOST and one FOUND report. | 4.430 | 2.212 | 1.859 | 2.834 | Seq Scan, Index Scan |
| W9 | WRITE | Change a suggested match to UNDER_REVIEW. | 0.362 | 0.189 | 0.145 | 0.232 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |
| W10 | WRITE | Submit proof of ownership for an existing candidate match. | 0.612 | 0.334 | 0.274 | 0.407 | Seq Scan, Index Scan, Index Only Scan |
| W11 | WRITE | Approve a claim with a DIFFERENT verifier and timestamp. | 0.597 | 0.324 | 0.311 | 0.411 | Index Scan, Seq Scan |
| W12 | WRITE | Record the item handover after verified approval. | 0.522 | 0.311 | 0.215 | 0.349 | Index Scan, Seq Scan |
| W13 | WRITE | Mark both reports RESOLVED only after a recorded handover. | 0.224 | 0.159 | 0.087 | 0.157 | Seq Scan |
| W14 | WRITE | Remove a photo from the report (example of an authorized edit). | 0.035 | 0.023 | 0.016 | 0.025 | Index Scan, Seq Scan |
| W15 | WRITE | Close a resolved item report after successful return. | 0.119 | 0.072 | 0.057 | 0.083 | Seq Scan |
| W16 | WRITE | Update a student's display name. | 0.031 | 0.025 | 0.016 | 0.024 | Index Scan |

## Analysis

These results measure the transaction-scoped
demonstration workload provided in AP CP3.

All write operations are rolled back.
No demonstration data is committed.

A sequential scan on a very small table
can be faster than an index lookup.

Execution times depend on database size,
cache state, system load, and disk activity.

This benchmark does not establish
production-scale performance.
