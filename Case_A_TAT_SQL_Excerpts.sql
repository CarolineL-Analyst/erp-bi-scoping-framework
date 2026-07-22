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

The core definition and source logic are FROZEN and confirmed by the client.
Post-freeze implementation validation is ongoing, and cancelled-project
population treatment remains pending stakeholder confirmation. A separate
visualization team renders the authoritative unit-level output and derives
nothing further.

ANONYMIZATION NOTE
All table names, column names, thresholds, and contract language have been
renamed, generalized, or paraphrased from the source.
Service levels are shown as A / B. Contractual thresholds are represented
through a generic TargetMinutes field; no original target values are included.
No customer data, customer names, or schema-identifying details are included.
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
EXCERPT 2 - Scoping holds to the reporting unit and preventing double-counting
--------------------------------------------------------------------------------
Holds are recorded per project and may serve different operational levels.
Where a hold is applied to a whole family, the ERP writes a separate record
against each affected project, which a child can then release independently -
so the database already states the intended scope of every hold.

The source logic first identifies the reporting unit, then uses only the holds
recorded against that unit's own project number. Parent and child holds may
cover the same calendar period, but they govern different clocks and are not
combined simply because the projects belong to the same family; inferring a
wider scope in SQL would override what the operator recorded.

Each applicable deductible hold is clamped to the reporting unit's measurement
window before its duration is calculated. Although the standard process does
not allow concurrent holds on a single project, overlapping intervals are
still merged into disjoint "islands" (a gaps-and-islands pattern) as a
defensive control for historical or unexpected data conditions. Raw per-reason
sums are retained as diagnostics, and a raw-minus-merged column makes any
unexpected overlap visible.
*/

-- #HoldDetail is populated by matching each reporting unit to hold records
-- on its own project number only: h.ProjectNo = u.ProjectNo.

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
EXCERPT 3 - Reporting unit by dispatch evidence, and structural data-quality guards
--------------------------------------------------------------------------------
The unit is the project carrying the qualifying outbound packing list. A family
is classified by where packing lists actually sit: assembled dispatch -> parent
is the unit; independent dispatch -> each child is a unit and the parent becomes
a reconciliation-only container.

The unit test is written against DISPATCH EVIDENCE, not hierarchy depth: once a
family's dispatch pattern is revealed, only projects carrying their own
qualifying outbound packing list become reporting units. This matters more than
it first appears. The family model was assumed to be two levels until output
reconciliation revealed a third - nested rework projects with no dispatch
evidence of their own, which a depth-based rule had been emitting as permanently
overdue phantom units. An evidence-based rule removes them without hard-coding
any maximum depth, so it also holds for structures not yet observed in the data.

Non-standard shapes are quarantined as data-quality exceptions rather than
guessed: more than one active receipt, more than one outbound packing list, and
records showing an item dispatched while its completion date is missing (a
contradiction under the confirmed workflow). In every case the metric columns
are set to NULL so the row physically cannot enter an attainment rate - the
guard is structural, not a note asking people to filter it out.
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
        WHEN u.DispatchedMissingCompletionFlag = 1 THEN NULL  -- workflow contradiction DQ
        WHEN u.TATStartDate IS NULL THEN NULL
        ELSE DATEDIFF_BIG(MINUTE, u.TATStartDate, u.TATEndDate)
             - ISNULL(mc.DeductMinutes, 0)
    END AS NetTATMinutes,

    CASE
        WHEN u.UnitType = 'Container' THEN 'Container - measured at child level'
        WHEN u.IsUnit = 0 THEN 'Data Quality - Mixed Parent/Child Dispatch Pattern'
        WHEN u.ActiveReceiptCount > 1 THEN 'Data Quality - Multiple Active Receipts'
        WHEN u.TotalOutboundPLCount > 1 THEN 'Data Quality - Multiple Packing Lists'
        WHEN u.DispatchedMissingCompletionFlag = 1
            THEN 'Data Quality - Dispatched but Completion Date Missing'
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
            definition. Three further categories were found the same way -
            an unguarded cardinality gap, a unit-generation defect from an
            unobserved hierarchy level, and a source-data contradiction -
            each corrected as a controlled fix.
Excerpt 2 - technical depth: project-level hold scoping followed by a
            gaps-and-islands merge retained as a defensive control against
            unexpected overlap within the same reporting unit.
Excerpt 3 - governance by construction: non-standard shapes are made visible
            and given NULL metrics so they cannot silently enter a rate.

The full script additionally carries a fully confirmed hold-reason treatment
map, an unmapped-reason conservative default, minute-precision integer
judgment, three output roles (authoritative unit-level dataset; monthly by
customer and department; monthly customer overall), and an explicit
handoff block instructing the visualization layer to consume the unit-level
output and recompute nothing. Operational interpretation is documented
separately in the dashboard guide, which translates source statuses into user
actions without altering the calculation.
*/
