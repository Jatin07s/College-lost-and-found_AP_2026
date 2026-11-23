from pathlib import Path
import re
import statistics
import subprocess
import tempfile

DB = "college_lost_found_cp3_verify"
SOURCE = Path("dbms/04_queries.sql")
REPORT = Path("dbms/05_query_timings.md")
PLAN_DIR = Path("dbms/plans")

expected = (
    [f"R{i}" for i in range(1, 17)]
    + [f"W{i}" for i in range(1, 17)]
)

source = SOURCE.read_text()

if not re.search(r"(?m)^ROLLBACK;\s*$", source):
    raise SystemExit("ERROR: ROLLBACK missing")

if re.search(r"(?im)^\s*COMMIT\s*;", source):
    raise SystemExit("ERROR: COMMIT found")

descriptions = {}
parts = []
pending = None

for line in source.splitlines(keepends=True):
    match = re.match(
        r"^-- (READ|WRITE) ([RW]\d+):\s*(.*)",
        line
    )

    if match:
        if pending:
            raise SystemExit(f"Missing SQL for {pending}")

        qid = match.group(2)
        descriptions[qid] = match.group(3)

        parts.append(f"\\echo AP_CP4_START {qid}\n")
        pending = qid

    if pending and re.match(
        r"^\s*(SELECT|INSERT|UPDATE|DELETE|WITH)\b",
        line,
        flags=re.I
    ):
        parts.append("EXPLAIN (ANALYZE, BUFFERS)\n")
        pending = None

    parts.append(line)

if set(descriptions) != set(expected) or pending:
    raise SystemExit("ERROR: Expected 32 queries")

parts.append("\n\\echo AP_CP4_FINISHED\n")
instrumented = "".join(parts)

timings = {q: [] for q in expected}
plans = {q: [] for q in expected}

for run in range(1, 4):
    print(f"Running benchmark {run}/3...", flush=True)

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".sql",
        delete=False
    ) as temp:
        temp.write(instrumented)
        filename = temp.name

    try:
        result = subprocess.run(
            [
                "psql",
                "-X", "-q", "-A", "-t",
                "-P", "pager=off",
                "-v", "ON_ERROR_STOP=1",
                "-d", DB,
                "-f", filename
            ],
            capture_output=True,
            text=True
        )
    finally:
        Path(filename).unlink(missing_ok=True)

    if result.returncode != 0:
        raise SystemExit(
            "Benchmark failed:\n" + result.stderr
        )

    if "AP_CP4_FINISHED" not in result.stdout:
        raise SystemExit("ERROR: Script did not finish")

    chunks = re.split(
        r"(?m)^AP_CP4_START ([RW]\d+)\s*$",
        result.stdout
    )

    if len(chunks) != 65:
        raise SystemExit(
            f"ERROR: Expected 32 plans, "
            f"found {(len(chunks)-1)//2}"
        )

    found = []

    for i in range(1, len(chunks), 2):
        qid = chunks[i]
        plan = chunks[i + 1].strip()

        matches = re.findall(
            r"Execution Time:\s*([\d.]+)\s*ms",
            plan
        )

        if len(matches) != 1:
            raise SystemExit(
                f"ERROR: Invalid timing for {qid}"
            )

        found.append(qid)
        timings[qid].append(float(matches[0]))
        plans[qid].append(
            f"===== {qid} RUN {run} =====\n"
            + plan + "\n"
        )

    if set(found) != set(expected):
        raise SystemExit("ERROR: Query list mismatch")

PLAN_DIR.mkdir(parents=True, exist_ok=True)

report = [
    "# AP CP4 — Query Execution Timings",
    "",
    "## Methodology",
    "",
    "- Database: PostgreSQL 16.",
    "- Source: `dbms/04_queries.sql`.",
    "- Method: `EXPLAIN (ANALYZE, BUFFERS)`.",
    "- Every query measured 3 times.",
    "- Average = mean of the three execution times.",
    "- Demo writes execute inside BEGIN/ROLLBACK.",
    "- Raw plans saved under `dbms/plans/`.",
    "",
    "## Timing Results",
    "",
    "| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |",
    "|---|---|---|---:|---:|---:|---:|---|"
]

for qid in expected:
    values = timings[qid]
    avg = statistics.mean(values)

    full_plan = "\n".join(plans[qid])
    (PLAN_DIR / f"{qid}.txt").write_text(full_plan)

    scan_pattern = (
        r"\b(?:Index Only Scan|Index Scan|"
        r"Seq Scan|Bitmap Heap Scan|"
        r"Bitmap Index Scan)\b"
    )

    scan_types = re.findall(
        scan_pattern,
        plans[qid][-1]
    )

    scan_types = list(dict.fromkeys(scan_types))
    scans = ", ".join(scan_types) or "No scan node"

    query_type = (
        "READ" if qid.startswith("R") else "WRITE"
    )

    description = descriptions[qid].replace("|", "/")

    report.append(
        f"| {qid} | {query_type} | {description} | "
        f"{values[0]:.3f} | "
        f"{values[1]:.3f} | "
        f"{values[2]:.3f} | "
        f"{avg:.3f} | {scans} |"
    )

report += [
    "",
    "## Analysis",
    "",
    "These results measure the transaction-scoped",
    "demonstration workload provided in AP CP3.",
    "",
    "All write operations are rolled back.",
    "No demonstration data is committed.",
    "",
    "A sequential scan on a very small table",
    "can be faster than an index lookup.",
    "",
    "Execution times depend on database size,",
    "cache state, system load, and disk activity.",
    "",
    "This benchmark does not establish",
    "production-scale performance.",
    ""
]

REPORT.write_text("\n".join(report))

print("\nSUCCESS: AP CP4 completed")
print("32 queries measured 3 times each")
print("96 executions measured")
print("32 raw plan files generated")
print("Report:", REPORT)
