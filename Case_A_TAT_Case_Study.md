# Case A — Contractual Turnaround Time (TAT) Against Target

*A KPI definition and source-logic case study. Anonymized: identifiers,
thresholds, and contract language are synthetic; the reasoning and structure
are unchanged.*

---

## 1. Context

I led the source-logic design for a KPI dashboard engagement with an aviation
MRO operator running on its MRO ERP platform. The engagement covered a broad, cross-functional KPI portfolio spanning
logistics, inventory, finance, commercial, project management, and operations. Across these I owned business definition through to delivered SQL
— running the discovery sessions with the client, validating data readiness
and process behaviour inside the ERP, deciding v1 scope versus future
enhancement, and preparing the confirmed source logic handed to a separate
visualization team. The visualization team builds the UI; it does not
re-derive the numbers.

---

## 2. The request, on the surface

The client's opening ask was simple: measure the turnaround time from
receiving a unit to shipping it back, and report whether each job hit or
missed its contractual target. Two service levels applied, each with its own
target window.

---

## 3. Framing the KPI in three layers

Rather than treat this as one calculation, I framed it as three independent
decisions, each settled on its own terms:

**How the duration is measured.** The contract fixes both ends: the clock
starts when the unit is physically received and stops at the agreed outbound-readiness milestone. In the ERP these map to the backdated receipt
date (reflecting physical receipt, not data-entry time) and the outbound
packing list completion date (the moment the return shipping label is
generated). Duration is measured to whole-minute precision — the target
tolerance is tight, and coarser precision introduces rounding noise that can
flip a borderline job between hit and miss for no meaningful reason.

**How a result is judged.** Only a project with a completed outbound packing
list is treated as completed and assessed as Hit or Miss. A project without
one is not yet judgeable; it is reported as Open — within target, or Open —
overdue, for live monitoring only. Folding not-yet-finished jobs into the
attainment rate would make the rate optimistic and unstable, and would
silently restate history as those jobs later closed.

**Which records count as a unit.** The ERP supports two-level parent/child
project structures, and projects can be detached (on detach the parent
reference clears, but the original parent is retained in a separate field, so
a detached project can still inherit its receipt-date start). The choice of
what constitutes one measurable deliverable turned out to drive the entire
denominator — and it is the subject of the next section.

---

## 4. Three decisions that defined the work

### 4.1 Deducting holds without double-counting

Some hold reasons pause the clock (customer-attributable waiting); others do
not (internal queue time). Because holds are the core driver of the metric, I
tested the hold table's behaviour carefully. Two facts shaped the design.
First, a single project cannot hold concurrently: the ERP requires a hold to
be released before another is applied, so one project's holds never overlap
each other. Second, holds are recorded per project — so when a parent and a
child project are held over the same period, they appear as two separate rows
on two different projects.

That second fact is the trap, and it only bites once the reporting unit is a
family. When the deductible holds of a parent and its children are combined,
their periods can overlap — and naively summing each hold's duration would
deduct the shared time twice, quietly shrinking net TAT and inflating the hit
rate. The error would be invisible at the dashboard layer; nothing on screen
would look wrong. To prevent it, I clamp each deductible hold to the
measurement window and merge overlapping intervals into disjoint periods
before measuring the deduction, so the same minute is never subtracted twice.
The raw per-reason sums are retained as diagnostics, and a raw-minus-merged
column makes any overlap visible per project.

### 4.2 The structural question that changed the denominator

The hold mapping was validated, all but one reason was mapped, and I was
waiting on the client to rule on the last one. With the master calculation essentially in place, I deliberately tested how
the definition behaved under the project hierarchy — a case I had not yet
exercised: what happens when a parent has children? If a parent has children,
which level raises the packing list? Since packing list completion is the
contractual end point, the answer wasn't a detail — it could move the end
point itself.

I went into the client's data. I found a parent project with several
children, each completed, each with its own packing list, each shipped back
to the customer independently — and the parent carrying no packing list at
all, acting purely as a container. That surfaced the decision the whole KPI
turned on: is the reporting unit the family, or the individual child? With
five children where four hit target and one missed, a per-family unit records
one Miss and understates both the workload and the real performance; a
per-child unit records four Hits and one Miss, reflecting what actually
happened on the floor.

A second question followed from the first: if packing list completion defines
the end point, does each project have exactly one? I ran the distribution
across a large historical project dataset. The overwhelming majority had
exactly one completed packing list — clearly the standard process. I looked
into the small remainder with more, including the spread between first and
last completion, which ranged from zero up to years apart. Inspecting the
outliers, the extra documents weren't additional dispatches: the operator had
raised an inbound packing list to mirror the customer's shipment in, then an
outbound one when the repaired item shipped back. The anomaly wasn't
multi-shipment; it was a second document type sharing one table.

### 4.3 Anchoring the decision in the contract, and closing it through process

Rather than send the client two open questions and wait, I re-read their
end-customer contract for the exact wording. The end point is defined as the
moment the supplier can evidence that the item has reached the agreed outbound-readiness milestone. That language decides the
unit: the obligation is per part, so the measurable unit is each
independently returnable deliverable — the project against which the
qualifying outbound packing list is completed. Where items reassemble into
one unit before return, that is the parent; where items return independently,
each child is its own unit. The container parent stays in the output for
reconciliation but carries no TAT result.

On the packing list question, I chose a process rule over a data workaround. I
could have written direction-detection logic to tell inbound records from
outbound ones, but that would mean maintaining a fragile mapping against a
free-form address table — the kind of rule that grows and breaks. Instead I
proposed formalising what the data already showed was standard: one qualifying
outbound packing list per deliverable project. Projects that violate this —
historically or in future — are flagged as data-quality exceptions and held
out of the rates until reviewed, rather than having a completion date guessed
for them. A rare, non-standard case doesn't warrant an invented rule; it
warrants visibility. The KPI cannot carry the whole burden alone — some of it
belongs to process discipline, and my job is to state clearly where that line
falls.

I sent the client a recommendation to confirm or correct — not a set of
questions to answer, but a decision they could say yes to, anchored in their
own contract and their own data. They confirmed it, and the definition was
frozen.

---

## 5. A governance pattern, not a one-off

One principle runs through every one of these decisions: **make predictable downstream errors difficult or impossible by construction, rather than relying on documentation alone.** Wherever a
downstream mistake could occur, the design closes it off in the data itself
rather than in a note asking people not to make it.

- Minute precision with integer comparison removes the rounding ambiguity at
  the hit/miss boundary — the judged value and the displayed value cannot
  disagree.
- Overlapping parent/child holds are merged, so double deduction cannot
  happen even when a family's holds coincide.
- Container parent projects stay in the output for traceability but carry
  null TAT values, so no aggregation can sweep them into a rate by accident.
- Unmapped hold reasons default conservatively (counted in TAT, never
  improving the metric) and are surfaced with a flag, so a newly added reason
  can't silently distort the number.
- Multi-packing-list projects, mixed-dispatch families, and multiple active
  receipts are all flagged as exceptions and held out of the rates rather
  than resolved by an invented fallback.

While one hold reason awaited a ruling, it was held as TBC and counted
conservatively, with a sensitivity column quantifying the alternative. The
resolution came from the contract itself: I recommended splitting the reason
by accountability — a standard regulatory process (customer-attributable,
clock stops) versus a supplier-side issue requiring action (clock runs) — and
the client adopted the split, adding the distinct hold types. Applying it was
exactly what the design promised: a map update, zero rework of the
calculation logic.

Alongside these, the definition states its **preconditions** explicitly — the
boundary between what the KPI owns and what the process must uphold: receipt
timestamps reflecting actual physical receipt; holds applied and released in
real time against the right project; packing lists marked complete when the
label is generated; one outbound packing list per deliverable project; and a
governance loop requiring any new hold reason to be reviewed and mapped before
it can affect the metric.

These preconditions were not left implicit in the definition document. Before
go-live, I turned them into a short operational guidance note for the client's
receiving and workshop teams — how to record receipts, how to place holds
against the right project in each parent/child scenario, and the notification
loop for new hold reasons — and sent it proactively, with the rationale that a
KPI is only as reliable as the data entered against it, and that habits are
cheaper to set before go-live than to correct after. Nobody had asked for it;
the client's response made clear it landed as a genuine value-add rather than
extra process. Treating data quality as something to design for at the source,
not audit for later, is part of what I think it means to own a metric rather
than just build it.

The real-time-holds precondition is not theoretical. The ERP timestamps a hold
to the minute when it is applied on the day, but a back-dated hold or release
is stored at midnight, losing the intra-day time. I quantified the exposure:
across tens of thousands of holds, a low single-digit share had a back-dated release, and
effectively none were same-day zero-duration holds. The effect is small and
one-directional — a back-dated release understates the deduction, which makes
a project marginally more likely to miss, never to falsely pass. Small and
conservative was enough to handle it as a stated precondition rather than to
over-engineer a correction that would only be guessing at the true time. The
visualization team's instruction is correspondingly narrow: render the source
output, add nothing that isn't in it.

This same discipline held after the definition was frozen. Representative-case
reconciliation later surfaced two implementation defects in the receipt lookup
— blank-string project references becoming a false anchor, and cancelled
receipts not being excluded — which together made one project show hundreds of
unrelated receipts and a start date years too early. I treated these as
controlled implementation fixes, not definition changes: the agreed business
rule never changed; the code was corrected to match it, and the fixes were
logged against the frozen definition. Distinguishing "the definition is wrong"
from "the implementation doesn't yet match the definition" is what lets a
frozen metric stay frozen while still being corrected.

---

## 6. Where it stands

The client confirmed the per-deliverable reporting unit and the single-
outbound-packing-list rule, and the KPI is now frozen as confirmed source
logic. The same reporting-unit and governance framing applies directly to
several further KPIs that depend on this master calculation. The framing
itself — three layers of definition, structural safeguards, and preconditions
as an explicit responsibility boundary — isn't specific to this KPI or to MRO;
it is how I take any contested metric from a vague request to something a
reporting team can build on without re-deriving it.
