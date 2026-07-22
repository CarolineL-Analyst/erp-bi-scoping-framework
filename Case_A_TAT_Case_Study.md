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

**Which records count as a unit.** The project structure was initially
understood as a two-level parent/child model, and projects can also be detached
(on detach the current parent reference clears, while the original parent is
retained separately, so a detached project can still inherit its receipt-date
start). Later output reconciliation revealed a nested third level — reinforcing
that reporting-unit logic could not safely depend on a fixed hierarchy depth.
The choice of what constitutes one measurable deliverable turned out to drive
the entire denominator — and it is the subject of the next section.

---

## 4. Three decisions that defined the work

### 4.1 Scoping holds to the reporting unit

Some hold reasons pause the clock (customer-attributable waiting); others do
not (internal queue time). Because holds are the core driver of the metric, I
tested the hold table's behaviour carefully. Two facts shaped the design.
First, a single project cannot hold concurrently: the ERP requires a hold to
be released before another is applied, so one project's holds never overlap
each other. Second, holds are recorded per project — and where a hold is
applied to a whole family, the ERP writes a separate record against each
affected project, which a child can then release independently.

Those separate records serve different operational levels and must not be
combined simply because the projects belong to the same family. The source
logic first identifies the reporting unit, then uses only the holds recorded
against that unit's own project number. For example, if one child is blocked
but the other children can continue, the affected child is held individually;
if that blockage also delays the final assembled deliverable, the parent is
held separately, without applying the parent hold to every child. Each
reporting unit therefore deducts only the hold time governing its own clock.
The database already states the intended scope of every hold explicitly —
inferring it in SQL would override what the operator recorded.

Each applicable hold is clamped to that unit's measurement window before its
duration is calculated. Interval merging is retained as a defensive control
for historical or unexpected overlap within the same reporting unit, even
though the standard process should not allow concurrent holds on one project.
Raw per-reason totals remain available as diagnostics, and a raw-minus-merged
value exposes any unexpected overlap.

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
- Hold deductions are scoped to the reporting unit's own project records;
  interval merging remains as a defensive control against unexpected overlap
  within that unit.
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

This same discipline held after the definition was frozen — and it is where
most of the real work happened. Freezing a definition is not the end of
validation; it is the point at which you can finally tell the difference
between a definition problem and an implementation problem. Reconciling the
output row by row surfaced four distinct categories of issue, each needing a
different response:

- **Source-association defects.** Blank-string project references were not
  being treated as null, so a blank value became a false receipt anchor and
  matched a large pool of unrelated historical records; cancelled receipts were
  not excluded. Together these gave one project hundreds of spurious receipts
  and a start date years too early.
- **An unguarded cardinality gap.** The standard is exactly one active receipt
  per anchor, but nothing enforced it. Rather than quietly picking the earliest
  date when more than one existed, I made that case a visible exception with no
  calculated result — the same treatment already used for ambiguous endpoints.
- **A unit-generation defect from an unobserved structure.** The family model
  was assumed to be two levels. Reconciliation revealed a third: nested rework
  projects, sitting under an intermediate sub-project, with no dispatch
  evidence of their own — several hundred of them emitted as permanently
  overdue phantom units. The fix was deliberately generic: once dispatch
  evidence exists, only projects carrying their own qualifying outbound packing
  list become reporting units. Written against evidence rather than hierarchy
  depth, that rule also covers structures I had not yet seen.
- **A source-data contradiction.** Some records showed an item as dispatched
  while its completion date was blank — impossible under the confirmed
  workflow. These were isolated as their own data-quality status rather than
  reported as ordinary overdue work, because a dispatched item with a missing
  timestamp and a job that genuinely hasn't finished mean opposite things
  operationally.

Every one of these was a controlled implementation fix, not a definition
change: the agreed business rule never moved; the code was corrected to match
it, and each correction was logged against the frozen definition. Distinguishing
"the definition is wrong" from "the implementation doesn't yet match the
definition" is what lets a frozen metric stay frozen while still being
corrected.

The same reconciliation raised two questions that were *not* mine to settle.
Internal projects — the operator's own work — were being measured against a
commitment that only applies to external customers, and could never close; I
excluded them in the source logic as a reversible working treatment, because a
dashboard-level filter cannot be applied to department views where internal and
contractual work share a department. Cancelled projects were less clear-cut:
profiling showed that cancelling a job does not necessarily end the return
process, and in most of the cases I found the item had gone on to reach the
confirmed endpoint. Whether the metric covers only completed work, or all
received items through return shipment, is a contract-scope question — so I put
it back to the client as a business-definition decision rather than imposing a
technical rule. Knowing which of these two piles a problem belongs in is, I
think, the more useful half of the skill.


The final gap was adoption. A correct source output can still be misused when
completed performance results, live operational risk, reconciliation rows, and
source-data contradictions appear together. I therefore prepared a dashboard
interpretation guide that moves users from the summary view to the relevant
unit, explains each status, and maps it to the next action. It complements the
pre-go-live operational guidance: one protects how evidence is entered; the
other protects how the output is interpreted and acted on. Neither was part of
the original request, but both close a gap between a technically correct
deliverable and operational value.

Together, the work closes three distinct gaps: source-data practice before
go-live, implementation fidelity through post-freeze reconciliation, and user
adoption through status-to-action guidance. The hidden rigor in the source
logic becomes visible to users when, for example, **Shipped but completion date
missing** does not appear as ordinary overdue work, but as a clear instruction
to correct the completion evidence rather than infer an endpoint.

---

## 6. Where it stands

The client confirmed the per-deliverable reporting unit and the single-
outbound-packing-list rule, so the core KPI definition and source logic are
frozen. Post-freeze implementation validation is still being completed, and
the cancelled-project population treatment remains pending client
confirmation. The same reporting-unit and governance framing applies directly
to several further KPIs that depend on this master calculation. The framing
itself — three layers of definition, structural safeguards, and preconditions
as an explicit responsibility boundary — isn't specific to this KPI or to MRO;
it is how I take any contested metric from a vague request to something a
reporting team can build on without re-deriving it.
