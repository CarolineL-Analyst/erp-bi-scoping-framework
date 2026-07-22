# How to Read the TAT Dashboard

**Case A — Contractual Turnaround Time Against Target**
*Operational interpretation guide — prepared for client handoff, pending final source validation*

---

*Anonymized portfolio version. Identifiers, thresholds, field names, and worked
examples are synthetic; the structure and reasoning are unchanged from the
working document.*

**Audience:** operations managers, project managers, department leads, and ERP
data owners.

**Why this document exists:** a correct metric that nobody knows how to read is
not yet a delivered metric. This guide is the adoption layer that follows
definition, source validation, and implementation — it tells operational users
how to move from a summary number to the specific record and the specific
action, and how to tell a genuine performance exception apart from a
data-quality condition that needs source correction.

This guide complements the operational-practice guidance prepared for the
receiving and workshop teams: that document protects how source evidence is
recorded; this guide protects how the resulting metric is interpreted and
acted on.

---

## 1. What the dashboard measures

Turnaround time (TAT) measures elapsed time from the confirmed receipt event to
completion of the qualifying outbound packing list. Approved deductible hold
time is removed before the result is compared with the applicable service-level
target.

> **Receipt** → elapsed time − approved holds = **Net TAT vs target**

### Four principles to remember

| Principle | Operational meaning |
|---|---|
| **Start** | The clock begins at the authoritative receipt date for the reporting unit or its confirmed receipt anchor. |
| **Pause** | Only hold reasons mapped as deductible are removed. Holds that count in TAT remain inside the clock. |
| **End** | The confirmed end event is outbound packing list completion. Project status is not used as a substitute endpoint. |
| **Result** | Closed units are classified Hit or Miss. Open units show live risk. Data-quality rows stay visible but do not enter attainment or averages. |

### Do not read this as a project-status report

A project may be closed in the ERP while the required packing list completion
evidence is missing, or it may remain open after dispatch. The KPI follows the
confirmed receipt-to-dispatch evidence chain, not the administrative project
status. This distinction is the single most common source of misreading.

---

## 2. Move through the dashboard in three levels

| View | What it shows | Primary question | Population |
|---|---|---|---|
| **1. Customer overview** | Headline monthly attainment by customer | Which customers show declining attainment or a high number of missed units? | Closed units only |
| **2. Department view** | Monthly attainment by customer and department | Which work area is driving the customer-level result? | Closed units only |
| **3. Project detail** | Unit-level detail, live open work, containers, and data-quality exceptions | Which individual units need review, validation, or corrective action? | Closed, open, container, and DQ rows |

### Recommended review rhythm

| Frequency | Focus | Typical action |
|---|---|---|
| **Daily** | Overdue units, units approaching target, new data-quality exceptions | Operational follow-up, or correct the source evidence |
| **Weekly** | Department patterns, missed completions, hold usage, unresolved DQ rows | Assign owners and agree corrective actions |
| **Monthly** | Closed attainment trend by customer and department | Review performance drivers and improvement priorities |

### A practical reading sequence

1. Check the customer overview for the current attainment picture.
2. Move to the department view to find the work area driving the result.
3. Open project detail for missed, overdue, or review-required rows.
4. **Confirm the unit type before interpreting a row as an independent deliverable.**
5. Use the status to decide whether the next action is operational follow-up or source-data correction.
6. After the authorized ERP owner corrects the source data, allow the next refresh to recalculate the row automatically.

> **Aggregation rule:** customer-level attainment is recomputed from unit-level
> results. Department percentages are never averaged together to produce an
> overall customer percentage.

---

## 3. How to read the project detail view

This view is the operational evidence layer. It carries more information than a
normal KPI table because it must support live follow-up, family reconciliation,
and source-data review. Present the columns in bands rather than as one
undifferentiated grid.

### Band A — identify the business record

| Field | What it tells you | How to use it |
|---|---|---|
| Customer | The external customer whose target profile applies | Filter or group the review |
| Project no. | The project carrying the TAT unit or reconciliation row | Locate the source record in the ERP |
| Department | The work area accountable for the reporting unit | Ownership and department-level analysis |
| Unit type | Whether the row is an independent unit, a container, a provisional root, or a DQ family row | **Confirm before treating the row as a performance result** |
| Root project no. | The family anchor for related parent/child projects | Review the full family when one row looks unusual |

### Band B — understand the clock

| Field | What it tells you | How to use it |
|---|---|---|
| Receipt date | The authoritative start date when one valid receipt exists | Confirm the clock starts from the expected receipt |
| Completed packing list date | The confirmed endpoint for a closed unit | A blank value means the unit is open or the endpoint evidence is incomplete |
| Deductible hold days | Merged hold time removed from the clock | Review where a result differs from gross elapsed time |
| Net TAT days | Elapsed time after approved hold deduction | Compare with the target |
| Target days | The applicable service-level target for that customer profile | The performance threshold |

### Band C — decide what action is needed

| Field | What it tells you | How to use it |
|---|---|---|
| Status | The authoritative interpretation of the row | See section 4 |
| Packing list count | How many qualifying outbound packing lists are attached | More than one is a DQ exception requiring review |
| Active receipt count | How many valid active receipt records exist for the anchor | More than one prevents a safe start-date selection |
| Unmapped hold indicator | A hold reason exists that has not yet been approved as count/deduct | Review and map the reason before relying on the result |
| Container child summary | Child unit count plus closed, hit, miss, open, and DQ totals | Use only on container rows, to understand family progress |

> **What stays hidden by default:** technical identifiers, raw minute fields,
> helper flags, inclusion flags, overlap diagnostics, and intermediate
> calculation fields remain available for reconciliation but do not belong in
> the default operational view.

---

## 4. Read the status before interpreting the numbers

The status answers the first operational question: is this a completed
performance result, a live unit, a reconciliation row, or a source-data
exception?

### Performance and live-work statuses

| Status | Meaning | Recommended action |
|---|---|---|
| **Closed — Hit** | Qualifying packing list complete; Net TAT at or below target | None. Use in attainment and trend analysis |
| **Closed — Miss** | Qualifying packing list complete; Net TAT exceeded target | Review the operational cause, holds, and department ownership |
| **Open — Within target** | Still open, currently within target | Monitor; prioritise units approaching target |
| **Open — Overdue** | Still open, elapsed time already exceeds target | Follow up operationally; confirm the outbound packing list is genuinely incomplete |
| **Container — measured at child level** | The root project is a family container; results sit on the packing-list-bearing children | Use the child summary; do not treat the container as another result |

### Data-quality and reconciliation statuses

| Status | Meaning | Recommended action |
|---|---|---|
| **Shipped but completion date missing** | The source shows the item dispatched while the packing list completion date is blank. Normal workflow requires completion first, so the two states contradict each other | Raise a source-data correction request with the authorized ERP support or data owner. **Do not infer an end date from project status** |
| **Multiple packing lists** | More than one qualifying outbound packing list exists for one intended reporting unit | Confirm whether the records are duplicates, historical, or evidence of a different dispatch pattern |
| **Multiple active receipts** | The receipt anchor carries more than one valid active receipt | Resolve the source duplication or identify the authoritative receipt |
| **Mixed parent/child dispatch** | The root and one or more children both carry outbound packing lists | Review the family manually. Do not assume one combined endpoint, and do not count both |
| **Missing receipt start date** | No single valid receipt start can be established | Correct the receipt evidence before the metric can be calculated |
| **Missing target** | The customer profile does not provide a valid target | Correct the customer target configuration |
| **Invalid date sequence** | The derived end date precedes the confirmed start date | Review source timestamps and data history |

> **Rule for DQ rows:** they stay visible in the detail view so they can be
> corrected. They do not contribute to closed attainment, average TAT, or
> normal overdue counts unless and until the source evidence is repaired.

---

## 5. Unit type and project-family logic

Unit type prevents double-counting. It identifies which project is the actual
returnable deliverable and which rows exist only to reconcile a family.

| Unit type | Business meaning | Treatment |
|---|---|---|
| **Standalone unit** | A project measured independently because it has no active family dispatch pattern. A closed unit carries its own qualifying outbound packing list; an open unit remains live until that evidence exists. | One independent result or live open unit |
| **Standalone unit (detached)** | A previously related project now measured independently, retaining its original receipt anchor for the start | One independent result or live open unit |
| **Parent unit** | The family is reassembled and the root carries the qualifying outbound packing list | One family-level result on the root |
| **Child unit** | A child project carries its own qualifying outbound packing list and is independently returnable | One result per packing-list-bearing child |
| **Container** | The root represents the family, but results are measured on the independently dispatched children | Reconciliation row only; use child summaries |
| **Provisional root (open)** | The family has no qualifying packing list yet, so the dispatch pattern cannot be observed | Temporary open unit; may reclassify once dispatch evidence appears |
| **DQ — mixed dispatch** | Both the root and one or more children carry qualifying outbound packing lists | Manual review only; no result until the correct pattern is confirmed |

### Normal family patterns

```
A. Reassembled / parent dispatch
   ROOT   [qualifying packing list]  -> Parent Unit (one result)
   CHILD  [no own packing list]      -> not a separate unit

B. Independent child dispatch
   ROOT   [no dispatch packing list] -> Container (reconciliation only)
   CHILD A [qualifying packing list] -> Child Unit (one result)
   CHILD B [qualifying packing list] -> Child Unit (one result)
```

### Why mixed dispatch is not calculated automatically

Where both the root and a child carry outbound packing lists, the data alone
cannot prove whether the family is one combined deliverable, several
independent deliverables, a duplicate document pattern, or an operational
exception. Selecting the latest completion date would silently assume they all
belong to one combined unit; counting both root and child would risk
double-counting. The safe treatment is manual review.

### Depth-independent rule

Once dispatch evidence exists, **only projects carrying their own qualifying
outbound packing list become reporting units.** A nested rework project without
its own packing list is not emitted as a phantom open unit, regardless of how
deep the family hierarchy goes. This rule is deliberately written against
dispatch evidence rather than hierarchy depth, so it holds even for structures
not yet observed in the data.

---

## 6. Worked examples

*Synthetic records, for illustration only.*

| Project | Unit type | Status | Net days | Target | Interpretation / next action |
|---|---|---|---|---|---|
| PRJ-SYN-1001 | Standalone unit | Closed — Hit | 12.4 | 15 | Completed within target. No correction required |
| PRJ-SYN-1027 | Child unit | Open — Overdue | 33.8 | 30 | Operational follow-up: confirm why the outbound packing list is incomplete |
| PRJ-SYN-1048 | Container | Container — measured at child level | — | — | Read the child summary: 5 units, 3 closed, 1 open, 1 DQ |
| PRJ-SYN-1089 | Child unit | Shipped but completion date missing | — | 15 | Raise a correction request with the authorized ERP owner; do not infer the completion date |
| PRJ-SYN-1112 | DQ — mixed dispatch child | DQ — mixed parent/child dispatch | — | 30 | Review the root family and determine the true dispatch pattern |

### Reading a container row

| Container summary | Value | How to read it |
|---|---|---|
| Child unit count | 52 | Fifty-two packing-list-bearing child units belong to the family |
| Child units closed | 40 | Forty have valid completed results |
| Child units hit / miss | 33 / 7 | Thirty-three met target; seven exceeded it |
| Child units open | 9 | Nine are still active and should be reviewed by status |
| Child units data quality | 3 | Three need source correction and are excluded from attainment |

> **Why the child totals may not add up as expected:** a project can look
> operationally complete in the ERP but stay outside "closed" when the
> qualifying packing list completion date is missing. That row appears under
> data quality rather than closed or open.

### The source-correction cycle

| Step | Action |
|---|---|
| 1 | The dashboard flags a dispatched item whose completion date is missing |
| 2 | The operational user reviews the packing list and confirms the expected completion evidence |
| 3 | The discrepancy is submitted to the authorized ERP support or data owner |
| 4 | The authorized owner corrects the source record through the approved support process |
| 5 | At the next refresh, the KPI uses the corrected completion date and the row moves to Closed — Hit or Closed — Miss |

This cycle is the point of the DQ statuses: they are not a dead end, they are a
work queue with a defined route back into the metric.

---

## 7. Review workflow

### Daily operational review

1. Filter to open units — overdue first, then those approaching target.
2. Sort live units by net elapsed days or remaining time to target.
3. **Review new data-quality statuses separately** from genuine operational overdue work.
4. Use project no., root project no., and unit type to understand the family before acting.
5. Assign source-data corrections to the ERP data owner, and operational delays to the accountable department.

### Weekly management review

1. Review customer and department attainment using closed units only.
2. Identify repeated misses, unresolved overdue units, and long-running DQ exceptions.
3. Review hold usage, especially unmapped or overlapping deductible holds.
4. Confirm that corrected source evidence has flowed through on the latest refresh.
5. Escalate repeated mixed-dispatch patterns for a business-process decision rather than a one-off workaround.

### Decision guide

| What you see | Treat it as | Next action |
|---|---|---|
| Closed — Miss | Confirmed historical performance miss | Investigate cause and improvement action |
| Open — Overdue | Live operational risk | Follow up on the incomplete outbound packing list |
| Shipped but completion missing | Source-data contradiction | Raise a correction request with the authorized ERP owner |
| Multiple receipts or packing lists | Non-unique start or end evidence | Identify the authoritative record |
| Mixed parent/child dispatch | Ambiguous reporting-unit pattern | Manual family review and business clarification |
| Container row | Family reconciliation | Use child summaries; do not count the container |

---

## 8. Scope notes and release requirements

### Population treatment in this version

- External customer projects with the applicable target profiles form the working population.
- The operator's own internal projects are excluded at source level in the working validation model, so they do not distort department-level results that cannot be filtered by customer.
- The treatment of cancelled projects remains a separate business-definition decision, referred to the client rather than inferred from technical status alone.

### To finalise before the live guide is issued

| Item | Release requirement |
|---|---|
| Representative-case reconciliation | Confirm known parent unit, child unit, container, detached, and mixed-dispatch examples |
| Population decisions | Record the confirmed treatment of internal and cancelled projects |
| Field mapping | Confirm final user-visible labels and which reconciliation fields stay hidden |
| Refresh behaviour | Replace the fixed validation timestamp with the production refresh time |
| User acceptance | Confirm that users can move from a status to the correct ERP action |
| Correction ownership | Confirm the authorized ERP support route, request owner, and evidence required for source-data corrections |

---

## Quick reference — one row in five questions

| Step | Question | Decision |
|---|---|---|
| 1 | What is the unit type? | Is this a result, a container, or a review-only DQ row? |
| 2 | What is the status? | Completed performance, live risk, or source-data exception? |
| 3 | What is the start and end evidence? | One valid receipt and one valid qualifying completion? |
| 4 | What changed the clock? | Were approved deductible holds applied? |
| 5 | What action follows? | Operational follow-up, source correction, or none? |

---

**Closing guidance for users:** use the summary views to understand
performance; use the detail view to understand evidence and action. Where the
evidence is incomplete or contradictory, route the issue through the authorized
ERP correction process rather than forcing the row into a performance category.
