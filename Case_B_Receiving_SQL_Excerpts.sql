/*
================================================================================
PORTFOLIO SAMPLE - Receiving Activity & Queue KPI (Case B)
Anonymized SQL excerpts from a validation-first KPI build
================================================================================

PROJECT CONTEXT

A paraphrased version of the opening request was:
    Provide periodic visibility into incoming and completed receiving activity.

Clarification showed the real intent was much broader: management visibility
over the entire Stores receiving operation. In the source ERP, "receiving" is
not one flow - it spans four distinct workflows, each with its own completion
semantics, grain, and date basis:

    1) Stock-related batch-to-stock receipts   (completion = batch record date)
    2) MRO receipts linked to workshop projects (completion = project link,
       with NO native link-date field - see Excerpt 1)
    3) Repair / Process receipts completed via receipt inspection
       (completion = inspection event date)
    4) Receiving hold / issue indicators        (see Excerpt 3)

The KPI was therefore designed as two separate dashboard concepts:
    - COMPLETED ACTIVITY : period-bound trends, one date basis per flow
    - CURRENT QUEUE      : as-of snapshot, intentionally NOT period-filtered,
                           aged against a fixed as-of timestamp

The full script (not reproduced here) contains a parameter block with an
effective-end-date cap for copied datasets, a structured sanity-check section run before any
reporting output was trusted, and multiple reporting and validation outputs (completed trends,
three queue views, a non-standard exception output, and a cross-flow hold
summary). The three excerpts below are chosen because each demonstrates a
different class of analytical decision.

ANONYMIZATION NOTE
All table names, column names, and type-code values have been renamed or
remapped from the source schema. No customer data, customer names, or
vendor-identifying schema details are included. Logic is unchanged.

REPRESENTATIVE SCHEMA (anonymized)
    ReceiptHeader      rh   receipt document header (ReceiptNo, ReceiptDate,
                            ReceiptType, OnHoldFlag, HoldDate, HoldComment,
                            FaultCodeID, PONoFK, CancelledFlag)
    ReceiptLine        rl   receipt line (ReceiptLineID, ReceiptNoFK,
                            StockReceiptedFlag, LinkedProjectRef)
    StockReceipt       sr   batch-to-stock record (ReceiptNoFK, BatchDate,
                            CancelledFlag)
    PurchaseOrder      po   purchase order header (PONo, OrderType)
    Project            p    workshop project master (ProjectNo, DateRaised)
    ReceiptInspection  ri   receipt inspection header (InspectionNo,
                            InspectionDate, ReceiptNoFK)

    ReceiptType / OrderType are illustrative synthetic constants declared below;
================================================================================
*/

SET NOCOUNT ON;

DECLARE @StartDate        datetime2(0) = '2024-01-01 00:00:00';  -- illustrative
DECLARE @EndDate          datetime2(0) = '2024-02-01 00:00:00';  -- illustrative
DECLARE @AsOfDateTime     datetime2(0) = '2024-01-15 12:00:00';  -- illustrative

-- In the full script, @EffectiveEndDate caps @EndDate at the data-copy
-- timestamp so that period-bound outputs on a copied/restored dataset never
-- imply data exists beyond the copy point. Simplified here:
DECLARE @EffectiveEndDate datetime2(0) =
    CASE
        WHEN @EndDate < @AsOfDateTime THEN @EndDate   -- cap at the earlier of
        ELSE @AsOfDateTime                            -- @EndDate / data-copy timestamp
    END;
-- Type codes below are illustrative synthetic constants (remapped from source),
-- declared once so no bare numeric code appears inline.
DECLARE @POReceiptType          int = 1;
DECLARE @MROReceiptType         int = 2;
DECLARE @ConsignmentReceiptType int = 3;
DECLARE @ExchangeReceiptType    int = 5;
DECLARE @LoanReceiptType        int = 6;
DECLARE @InternalReceiptType    int = 8;
DECLARE @OtherReceiptType       int = 9;
DECLARE @StockOrderType         int = 1;
DECLARE @RepairOrderType        int = 3;
DECLARE @WarrantyOrderType      int = 4;
DECLARE @ProcessOrderType       int = 7;
DECLARE @StockRepairOrderType   int = 8;
DECLARE @ServiceOrderType       int = 9;


/*==============================================================================
EXCERPT 1 - INFERRED COMPLETION DATE FOR THE MRO FLOW
             ("validate the rule before applying it")

Problem
  What COUNTS as completion for MRO receipts is confirmed: a receipt leaves the
  Parts at Dock pending queue when its line is linked to a workshop project -
  the real ERP queue-exit event. What is NOT stored is WHEN that link was made:
  there is no link-date field. The project may pre-exist the receipt (selected
  during receipt creation) or be raised afterwards, so neither the receipt date
  nor the project raised date is correct on its own. Only the DATE is inferred;
  the completion event itself is source-native.

Rule proposed
  - Project raised AFTER the receipt  -> completion date = project DateRaised
  - Project raised BEFORE / AT receipt -> completion date = receipt date
    (the link happened at receipt creation)
  - Reference populated but no matching project -> validation exception,
    excluded from the completion trend (no defensible date exists)

The scenario-distribution query below was run FIRST, to prove how the three
cases actually split in real data before the date-attribution rule was embedded. The reporting
query then applies the identical CASE logic - validation and application share
one definition, so they can never drift apart.

Note the reference-field normalization: LinkedProjectRef is a text field where
"not linked" can be NULL or a blank/whitespace string depending on entry
route, so every test uses NULLIF(LTRIM(RTRIM(...)), '').
==============================================================================*/

-- 1a. Scenario distribution: run before adopting the rule
SELECT
    CASE
        WHEN p.ProjectNo IS NULL
            THEN 'Reference populated but no matching project (validation exception)'
        WHEN p.DateRaised > rh.ReceiptDate
            THEN 'Project created after MRO receipt'
        ELSE 'Project existed before / at MRO receipt'
    END AS LinkDateScenario,
    COUNT(DISTINCT rh.ReceiptNo) AS MROReceiptCount,
    COUNT(*)                     AS MROReceiptLineCount,
    MIN(rh.ReceiptDate)          AS FirstReceiptDate,
    MAX(rh.ReceiptDate)          AS LastReceiptDate
FROM ReceiptHeader AS rh
JOIN ReceiptLine AS rl
    ON rl.ReceiptNoFK = rh.ReceiptNo
LEFT JOIN Project AS p
    ON p.ProjectNo = NULLIF(LTRIM(RTRIM(rl.LinkedProjectRef)), '')
WHERE
    rh.CancelledFlag = 0
    AND rh.ReceiptType = @MROReceiptType                          -- MRO receipt (parameterised)
    AND NULLIF(LTRIM(RTRIM(rl.LinkedProjectRef)), '') IS NOT NULL
GROUP BY
    CASE
        WHEN p.ProjectNo IS NULL
            THEN 'Reference populated but no matching project (validation exception)'
        WHEN p.DateRaised > rh.ReceiptDate
            THEN 'Project created after MRO receipt'
        ELSE 'Project existed before / at MRO receipt'
    END
ORDER BY
    LinkDateScenario;


-- 1b. Completed-activity trend applying the same inferred-date rule
WITH MROLinked AS (
    SELECT
        rh.ReceiptNo,
        CASE
            WHEN p.ProjectNo IS NULL THEN NULL   -- exception: excluded below
            WHEN p.DateRaised > rh.ReceiptDate THEN p.DateRaised
            ELSE rh.ReceiptDate
        END AS InferredCompletedDate,
        CASE
            WHEN p.ProjectNo IS NULL
                THEN 'Reference populated but no matching project (validation exception)'
            WHEN p.DateRaised > rh.ReceiptDate
                THEN 'Project created after MRO receipt'
            ELSE 'Project existed before / at MRO receipt'
        END AS LinkDateScenario
    FROM ReceiptHeader AS rh
    JOIN ReceiptLine AS rl
        ON rl.ReceiptNoFK = rh.ReceiptNo
    LEFT JOIN Project AS p
        ON p.ProjectNo = NULLIF(LTRIM(RTRIM(rl.LinkedProjectRef)), '')
    WHERE
        rh.CancelledFlag = 0
        AND rh.ReceiptType = @MROReceiptType
        AND NULLIF(LTRIM(RTRIM(rl.LinkedProjectRef)), '') IS NOT NULL
)
SELECT
    CAST(InferredCompletedDate AS date) AS ReportingDate,
    LinkDateScenario,
    COUNT(DISTINCT ReceiptNo)           AS MROReceiptCount
FROM MROLinked
WHERE
    InferredCompletedDate >= @StartDate          -- NULL (exception) rows
    AND InferredCompletedDate < @EffectiveEndDate -- excluded automatically
GROUP BY
    CAST(InferredCompletedDate AS date),
    LinkDateScenario
ORDER BY
    ReportingDate,
    LinkDateScenario;


/*==============================================================================
EXCERPT 2 - POPULATION GOVERNANCE: QUARANTINING AN AMBIGUOUS POPULATION

Problem
  A line-level "stock receipted" flag exists, but cross-checking it against
  actual batch records revealed a population flagged as received with NO
  corresponding batch record. These rows are ambiguous: some belong to
  legitimate flows that never create batch records (inspection-based receipt
  types, exchange flows); others may be genuinely stuck.

Decision
  Instead of silently including them in the queue (overstating backlog) or in
  completed activity (hiding stuck items), they were quarantined into a
  dedicated exception output, pre-classified by receipt/order type with a
  suggested treatment per subgroup. The flag itself was demoted: it defines
  queue membership only, never a completion date (completion dates come from
  batch records - a separate, validated decision).

This is the summary form; the full script also produces the record-level
detail with the same treatment mapping.
==============================================================================*/

SELECT
    rh.ReceiptType,
    po.OrderType,
    CASE
        WHEN po.OrderType IN (@RepairOrderType, @ProcessOrderType)
            THEN 'Likely inspection-based receipt flow - exclude from stock queue by default'
        WHEN rh.ReceiptType = @ExchangeReceiptType
            THEN 'Exchange flow / non-PO route - validate source route'
        ELSE 'Validation required before queue treatment'
    END AS SuggestedTreatment,
    COUNT(*)                      AS ReceiptLineCount,
    COUNT(DISTINCT rh.ReceiptNo)  AS ReceiptCount
FROM ReceiptLine AS rl
JOIN ReceiptHeader AS rh
    ON rh.ReceiptNo = rl.ReceiptNoFK
LEFT JOIN PurchaseOrder AS po
    ON po.PONo = rh.PONoFK
LEFT JOIN (                                   -- receipts having ANY batch record
    SELECT DISTINCT ReceiptNoFK
    FROM StockReceipt
    WHERE CancelledFlag = 0
      AND ReceiptNoFK IS NOT NULL
) AS sr
    ON sr.ReceiptNoFK = rl.ReceiptNoFK
WHERE
    rh.CancelledFlag = 0
    AND rl.StockReceiptedFlag = 1             -- flagged as received...
    AND sr.ReceiptNoFK IS NULL                -- ...but no batch record exists
GROUP BY
    rh.ReceiptType,
    po.OrderType,
    CASE
        WHEN po.OrderType IN (@RepairOrderType, @ProcessOrderType)
            THEN 'Likely inspection-based receipt flow - exclude from stock queue by default'
        WHEN rh.ReceiptType = @ExchangeReceiptType
            THEN 'Exchange flow / non-PO route - validate source route'
        ELSE 'Validation required before queue treatment'
    END
ORDER BY
    rh.ReceiptType,
    po.OrderType;


/*==============================================================================
EXCERPT 3 - CROSS-FLOW HOLD STATUS SUMMARY (as-of snapshot)

Problem
  Manual validation in the ERP UI showed that hold-related fields (HoldDate,
  HoldComment, FaultCodeID) REMAIN POPULATED after a hold is released. The
  initial rule - "any hold evidence = issue" - would therefore report released
  holds as active blockers forever, and the issue count could only ever grow.

Decision
  A three-tier model, with only the active flag defining a current blocker:
      1) Currently on hold        : OnHoldFlag = 1
      2) Previously held/released : OnHoldFlag = 0 with hold-history fields
                                    still populated (context, not blocker)
      3) No hold evidence

  The query unions the three current-queue definitions (one per flow) so
  management sees hold pressure across the whole receiving operation in one
  view. As a queue snapshot it is intentionally NOT period-filtered.
==============================================================================*/

WITH StockQueue AS (                          -- flow 1: not yet batched
    SELECT
        'Stock-related not yet batched' AS QueueFlow,
        rh.ReceiptNo, rh.ReceiptDate,
        rh.OnHoldFlag, rh.FaultCodeID, rh.HoldDate, rh.HoldComment
    FROM ReceiptHeader AS rh
    JOIN ReceiptLine AS rl
        ON rl.ReceiptNoFK = rh.ReceiptNo
    LEFT JOIN PurchaseOrder AS po
        ON po.PONo = rh.PONoFK
    WHERE
        rh.CancelledFlag = 0
        AND rl.StockReceiptedFlag = 0
        AND (
            (rh.ReceiptType = @POReceiptType AND po.OrderType IN (@StockOrderType, @WarrantyOrderType, @StockRepairOrderType, @ServiceOrderType))
            OR rh.ReceiptType IN (@ConsignmentReceiptType, @ExchangeReceiptType, @LoanReceiptType, @InternalReceiptType)
        )
),
MROQueue AS (                                 -- flow 2: awaiting project link
    SELECT
        'MRO awaiting project link' AS QueueFlow,
        rh.ReceiptNo, rh.ReceiptDate,
        rh.OnHoldFlag, rh.FaultCodeID, rh.HoldDate, rh.HoldComment
    FROM ReceiptHeader AS rh
    JOIN ReceiptLine AS rl
        ON rl.ReceiptNoFK = rh.ReceiptNo
    WHERE
        rh.CancelledFlag = 0
        AND rh.ReceiptType = @MROReceiptType
        AND NULLIF(LTRIM(RTRIM(rl.LinkedProjectRef)), '') IS NULL
),
InspectionQueue AS (                          -- flow 3: pending inspection
    SELECT
        'Repair / Process pending inspection' AS QueueFlow,
        rh.ReceiptNo, rh.ReceiptDate,
        rh.OnHoldFlag, rh.FaultCodeID, rh.HoldDate, rh.HoldComment
    FROM ReceiptHeader AS rh
    LEFT JOIN PurchaseOrder AS po
        ON po.PONo = rh.PONoFK
    LEFT JOIN (
        SELECT DISTINCT ReceiptNoFK
        FROM ReceiptInspection
        WHERE ReceiptNoFK IS NOT NULL
    ) AS ri
        ON ri.ReceiptNoFK = rh.ReceiptNo
    WHERE
        rh.CancelledFlag = 0
        AND ri.ReceiptNoFK IS NULL
        AND (po.OrderType IN (@RepairOrderType, @ProcessOrderType) OR rh.ReceiptType = @OtherReceiptType)
),
AllQueues AS (
    SELECT * FROM StockQueue
    UNION ALL
    SELECT * FROM MROQueue
    UNION ALL
    SELECT * FROM InspectionQueue
)
SELECT
    QueueFlow,
    CASE
        WHEN ISNULL(OnHoldFlag, 0) = 1 THEN 'Currently on hold'
        WHEN ISNULL(OnHoldFlag, 0) = 0
             AND (
                 HoldDate IS NOT NULL
                 OR FaultCodeID IS NOT NULL
                 OR NULLIF(LTRIM(RTRIM(CAST(HoldComment AS varchar(max)))), '') IS NOT NULL
             ) THEN 'Previously held / released'
        ELSE 'No hold evidence'
    END AS HoldStatus,
    COUNT(DISTINCT ReceiptNo) AS ReceiptCount,
    MIN(ReceiptDate)          AS OldestReceiptDate,
    MAX(ReceiptDate)          AS NewestReceiptDate
FROM AllQueues
GROUP BY
    QueueFlow,
    CASE
        WHEN ISNULL(OnHoldFlag, 0) = 1 THEN 'Currently on hold'
        WHEN ISNULL(OnHoldFlag, 0) = 0
             AND (
                 HoldDate IS NOT NULL
                 OR FaultCodeID IS NOT NULL
                 OR NULLIF(LTRIM(RTRIM(CAST(HoldComment AS varchar(max)))), '') IS NOT NULL
             ) THEN 'Previously held / released'
        ELSE 'No hold evidence'
    END
ORDER BY
    QueueFlow,
    HoldStatus;


/*==============================================================================
WHAT THE THREE EXCERPTS DEMONSTRATE

Excerpt 1  Deriving a defensible completion date where the source stores none:
           propose a conditional rule, validate its scenario distribution
           against real data first, then apply the identical logic in the
           reporting layer so validation and reporting cannot drift.

Excerpt 2  Population governance: an ambiguous population is quarantined into
           a named exception output with per-subgroup treatment, instead of
           being silently absorbed into the queue or the completed trend.

Excerpt 3  Semantic correction of a misleading source pattern (hold-history
           fields persisting after release), plus a cross-flow snapshot
           architecture that unions three independently-defined queues into
           one management view.

Together they reflect the project's core method: no reporting output was
published until the source behaviour behind it had been checked, quantified,
and confirmed, governed through a documented implementation convention, retained as an explicit non-blocking open item, or quarantined.
================================================================================
*/
