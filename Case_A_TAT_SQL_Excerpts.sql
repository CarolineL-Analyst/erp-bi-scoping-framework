/*
================================================================================
PORTFOLIO SAMPLE - Contractual Turnaround Time (TAT) Against Target (Case A)
Anonymized SQL excerpts from a frozen, validation-first KPI build
================================================================================

PROJECT CONTEXT

The client's request was to measure turnaround time from receiving a unit to
shipping it back, and report Hit/Miss against a contractual target. Two service
levels applied, each with its own target window.

What looked like one calculation was framed as three independent decisions:
  - how duration is measured (receipt -> outbound packing list completion,
    minus customer-attributable hold time, to whole-minute precision);
  - how a result is judged (only a completed unit is Hit/Miss; everything
    else is Open, monitored but excluded from attainment);
  - which record counts as one unit (the project carrying the qualifying
    outbound packing list - parent for assembled dispatch, each child for
    independent dispatch).

The definition is FROZEN and confirmed by the client. A separate visualization
team renders the authoritative unit-level output and derives nothing further.

ANONYMIZATION NOTE
All table names, column names, thresholds, and contract language have been
renamed, generalized, or paraphrased from the source. 

Service levels are shown as A / B. Contractual thresholds are represented
through a generic TargetMinutes field; no original target values are included. 

Logic is unchanged.

--------------------------------------------------------------------------------
EXCERPT 1 - Receipt anchor: normalizing blank references and excluding
            cancelled receipts (a controlled fix found after freeze)
--------------------------------------------------------------------------------
Representative-case reconciliation after the definition was frozen surfaced a
project showing hundreds of unrelated receipts and a start date years too
early. Two root causes: blank-string project references were not treated as
NULL (so a blank anchor matched a large pool of unrelated historical records),
and cancelled receipts were not excluded (cancelling a receipt does not clear
its project reference). The standard is exactly one active receipt per anchor;
more than one is a data-quality exception with no auto-selected start. This was
corrected as an implementation fix without changing the frozen definition.
*/

SELECT
    NULLIF(LTRIM(RTRIM(rl.AnchorProjectRef)), N'') AS AnchorProjectNo,
    MIN(r.ReceiptDate) AS EarliestActiveReceiptDate,
    MAX(r.ReceiptDate) AS LatestActiveReceiptDate,
    COUNT(DISTINCT r.ReceiptNo) AS ActiveReceiptCount           -- 1 = standard; >1 = DQ
INTO #Receipt
FROM dbo.ReceiptHeader AS r
INNER JOIN dbo.ReceiptLine AS rl
    ON rl.ReceiptNoFor = r.ReceiptNo
WHERE
    r.ReceiptType = @MROReceiptType
    AND ISNULL(r.Cancelled, 0) = 0                              -- exclude cancelled
    AND r.ReceiptDate IS NOT NULL
    AND r.ReceiptDate <= @AsOfDateTime
    AND NULLIF(LTRIM(RTRIM(rl.AnchorProjectRef)), N'') IS NOT NULL   -- exclude blank refs
GROUP BY
    NULLIF(LTRIM(RTRIM(rl.AnchorProjectRef)), N'');


/*
--------------------------------------------------------------------------------
EXCERPT 2 - Deducting holds without double-counting (interval merge)
--------------------------------------------------------------------------------
Holds are recorded per project. A single project cannot hold concurrently, but
once the reporting unit is a family, a parent hold and a child hold can cover
the same period. Naively summing each hold's duration would deduct the shared
time twice - invisible at the dashboard, quietly inflating the hit rate. Each
deductible hold is clamped to the measurement window, then overlapping
intervals are merged into disjoint "islands" (a gaps-and-islands pattern)
before the deduction is measured, so no minute is subtracted twice. Raw
per-reason sums are retained as diagnostics, and a raw-minus-merged column
makes any overlap visible.
*/

WITH DeductBase AS (
    SELECT UnitProjectNo, OverlapStartDate AS IntStart, OverlapEndDate AS IntEnd
    FROM #HoldDetail
    WHERE CountInTAT = 'No'                        -- deductible reasons only
      AND OverlapStartDate IS NOT NULL
      AND OverlapEndDate > OverlapStartDate
),
Ordered AS (
    SELECT *,
        MAX(IntEnd) OVER (
            PARTITION BY UnitProjectNo ORDER BY IntStart, IntEnd
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS PrevMaxEnd
    FROM DeductBase
),
Islands AS (
    SELECT *,
        SUM(CASE WHEN PrevMaxEnd IS NULL OR IntStart > PrevMaxEnd THEN 1 ELSE 0 END)
            OVER (PARTITION BY UnitProjectNo ORDER BY IntStart, IntEnd
                  ROWS UNBOUNDED PRECEDING) AS IslandID
    FROM Ordered
),
MergedIntervals AS (
    SELECT UnitProjectNo, IslandID,
           MIN(IntStart) AS IntStart, MAX(IntEnd) AS IntEnd
    FROM Islands
    GROUP BY UnitProjectNo, IslandID
)
SELECT
    UnitProjectNo,
    SUM(DATEDIFF_BIG(MINUTE, IntStart, IntEnd)) AS DeductMinutes,
    COUNT(*) AS MergedIntervalCount
INTO #HoldMerged
FROM MergedIntervals
GROUP BY UnitProjectNo;


/*
--------------------------------------------------------------------------------
EXCERPT 3 - Reporting unit by dispatch mode, and structural data-quality guards
--------------------------------------------------------------------------------
The unit is the project carrying the qualifying outbound packing list. A family
is classified by where packing lists actually sit: assembled dispatch -> parent
is the unit; independent dispatch -> each child is a unit and the parent becomes
a reconciliation-only container. Two non-standard shapes are quarantined as
data-quality exceptions rather than guessed: more than one active receipt, and
more than one outbound packing list. In every case the metric columns are set
to NULL so the row physically cannot enter an attainment rate - the guard is
structural, not a note asking people to filter it out.
*/

SELECT
    u.ProjectNo,
    u.UnitType,
    u.DispatchMode,
    u.ServiceLevel,                                -- A or B
    u.TargetMinutes,
    u.TATStartDate,
    u.TATEndDate,

    /* Net TAT is NULL for containers and for every data-quality exception,
       so no aggregation can sweep them into a rate by accident. */
    CASE
        WHEN u.IsUnit = 0 THEN NULL                        -- container / mixed-dispatch DQ
        WHEN u.ActiveReceiptCount <> 1 THEN NULL           -- multiple / missing active receipt
        WHEN u.TotalOutboundPLCount > 1 THEN NULL          -- multiple packing lists DQ
        WHEN u.TATStartDate IS NULL THEN NULL
        ELSE DATEDIFF_BIG(MINUTE, u.TATStartDate, u.TATEndDate)
             - ISNULL(mc.DeductMinutes, 0)
    END AS NetTATMinutes,

    CASE
        WHEN u.UnitType = 'Container' THEN 'Container - measured at child level'
        WHEN u.IsUnit = 0 THEN 'Data Quality - Mixed Parent/Child Dispatch Pattern'
        WHEN u.ActiveReceiptCount > 1 THEN 'Data Quality - Multiple Active Receipts'
        WHEN u.TotalOutboundPLCount > 1 THEN 'Data Quality - Multiple Packing Lists'
        WHEN u.ActiveReceiptCount = 0 OR u.TATStartDate IS NULL
            THEN 'Missing receipt start date'
        WHEN u.TotalOutboundPLCount = 1 AND u.CompletedOutboundPLCount = 1
             AND DATEDIFF_BIG(MINUTE, u.TATStartDate, u.TATEndDate)
                 - ISNULL(mc.DeductMinutes, 0) <= u.TargetMinutes
            THEN 'Closed - Hit'
        WHEN u.TotalOutboundPLCount = 1 AND u.CompletedOutboundPLCount = 1
            THEN 'Closed - Miss'
        WHEN DATEDIFF_BIG(MINUTE, u.TATStartDate, u.TATEndDate)
             - ISNULL(mc.DeductMinutes, 0) <= u.TargetMinutes
            THEN 'Open - Within Target'
        ELSE 'Open - Overdue'
    END AS TATStatus
FROM #Units AS u
LEFT JOIN #HoldMerged AS mc
    ON mc.UnitProjectNo = u.ProjectNo;


/*
--------------------------------------------------------------------------------
WHY THESE THREE
--------------------------------------------------------------------------------
Excerpt 1 - validation discipline: a defect caught by reconciling a
            representative case after freeze, fixed without reopening the
            definition.
Excerpt 2 - technical depth: a gaps-and-islands merge that prevents an
            invisible double-deduction once the unit is a family.
Excerpt 3 - governance by construction: non-standard shapes are made visible
            and given NULL metrics so they cannot silently enter a rate.

The full script additionally carries a fully confirmed hold-reason treatment
map, an unmapped-reason conservative default, minute-precision integer
judgment, three output roles (authoritative unit-level dataset; monthly by
customer and department; monthly customer overall), and an explicit
handoff block instructing the visualization layer to consume the unit-level
output and recompute nothing.
*/
