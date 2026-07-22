# ERP BI Scoping, KPI Definition & Source Logic

This portfolio shows how I take a vague business request and turn it into a
confirmed, auditable KPI definition and the source query a reporting team can
build on without having to re-derive the numbers. The work is drawn from an
aviation MRO ERP analytics engagement; all customer names, contract wording,
schema details, and internal identifiers have been anonymized or paraphrased,
and the examples use synthetic naming throughout.

My role on the engagement spanned business-definition discovery, data
validation inside the ERP, source-logic design in T-SQL, and the definition
governance that keeps a metric stable once it is agreed. A separate
visualization team builds the dashboards; my deliverable is the confirmed
definition and the authoritative dataset it consumes.

---

## What's here, and the order to read it

**Start with the framework, then go deep on one case.**

1. **KPI Scoping Framework** (`KPI_Scope_Matrix.xlsx`) — the method.
   One row per requested KPI, carrying each from a synthetic or paraphrased request through
   definition, risk triage, and readiness for estimate. Read the
   *Instructions* sheet first, then skim the matrix. This is the lens the
   rest of the portfolio applies.

2. **Case A — Contractual Turnaround Time (TAT)** — the flagship, and the
   piece to read if you only read one. Its four artifacts follow the delivery
   lifecycle:
   - `Case_A_TAT_Case_Study.md` — how the definition was reasoned out and
     frozen. Start here.
   - `Case_A_TAT_SQL_Excerpts.sql` — how it was implemented, including the
     structural guards.
   - `Case_A_Decision_Log.xlsx` — the decision trail, including the defects
     found after freezing and how each was classified.
   - `Case_A_Dashboard_Interpretation_Guide.md` — the adoption layer being
     prepared for operational handoff: what each status means and what action
     it implies for an operational user.

3. **Case B — Receiving Activity & Queue** — breadth evidence. Sanitized SQL
   excerpts and a decision log show the same method applied to a different
   problem shape (one request that unfolded into four distinct workflows).

4. **Supporting governance evidence** — the decision logs and the operational
   precondition material show how data quality, implementation changes, and
   definition stability are managed after the core rule is agreed.

---

## Numbering

Portfolio identifiers are internal to this portfolio and do not correspond to
any engagement's numbering.

- **Case A** and **Case B** are the two featured portfolio cases.
- **PF-01 … PF-15** identify the rows in the scoping framework (a
  representative excerpt of the wider scoping work). Case A is PF-01;
  Case B is PF-05.

---

## Framework origin

No BI scoping template was provided to me. After taking ownership of the
discovery and KPI-definition process, I found there was no structured way to
carry a request from "what the customer said" through to "what we can build
and defend," so I designed one: the field set, the definition-risk versus
data-readiness triage, the decision-tracking convention, and the
delivery-readiness status vocabulary. The version here is a simplified,
anonymized adaptation of the working framework. It is my own methodology
asset, not an internal company document.

---

## The through-line

One principle runs through every piece: **make predictable downstream errors difficult or impossible by construction, rather than relying on documentation alone.** Where a downstream
mistake could happen, the design closes it off in the data itself — judged
values and displayed values cannot disagree; container and data-quality rows
carry null metrics so they cannot be swept into a rate; anything uncertain is
made visible and held out of the numbers rather than guessed. The same
discipline extends past the query: each definition states the operational
preconditions it depends on and a governance loop for changes, so
data-quality risks are addressed upstream wherever possible, rather than
discovered only after dashboard delivery.

---

## A note on what these show

- **Judgment and validation discipline** — the case studies center on
  decisions where the obvious reading was wrong, and on catching those
  through assumption-testing against real data before a definition was
  frozen.
- **Definition governance** — freezing a metric, distinguishing a business
  definition from its implementation, and correcting implementation defects
  as controlled fixes without reopening the agreed definition. Case A shows
  four categories of defect found by reconciling output after the freeze, and
  two questions that were referred back to the client instead, because they
  were matters of contract scope rather than implementation.
- **Source-to-consumer handoff** — writing the authoritative dataset and the
  rules a reporting team consumes, so the metric stays consistent across
  every view built on it.
- **End-to-end value realization** — a correct query is not yet a delivered
  metric. Case A closes three gaps between definition and operational value:
  source-data practices before go-live, implementation fidelity through
  post-freeze reconciliation, and user adoption through a status-to-action
  interpretation guide.

*Contents are anonymized. Identifiers, thresholds, contract language, and
schema details have been replaced with synthetic equivalents; the reasoning
and structure are unchanged.*
