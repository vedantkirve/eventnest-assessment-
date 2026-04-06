# EventNest — Code Review

**Reviewer:** Claude Code
**Date:** 2026-04-07
**Scope:** Full codebase — security, data integrity, architecture, performance, testing

---

## Issue Index

| # | Title | Category | Severity | File |
|---|---|---|---|---|
| 1 | Broken Object-Level Authorization on Orders | Security | Critical | `orders_controller.rb` |
| 2 | SQL Injection in Event Search | Security | Critical | `events_controller.rb` |
| 3 | Event Ownership Never Verified on Mutations | Security | Critical | `events_controller.rb` |
| 4 | Ticket Inventory Race Condition (Oversell) | Data Integrity | Critical | `ticket_tier.rb` |
| 5 | `sold_count` Is Mass-Assignable via API | Security / Data Integrity | High | `ticket_tiers_controller.rb` |
| 6 | No State Machine — Invalid Order/Payment Transitions Allowed | Architecture | High | `order.rb`, `payment.rb` |
| 7 | No Foreign Key Constraints or Indexes on Any Relation | Performance / Data Integrity | High | All migrations |

---

## Issue #1 — Broken Object-Level Authorization on Orders

**File:** `app/controllers/api/v1/orders_controller.rb`
**Lines:** 6 (`index`), 22 (`show`), 81 (`cancel`)
**Category:** Security
**Severity:** Critical

The `index` action returns `Order.all` with no filter — every authenticated user receives every order in the database, regardless of who placed them. The `show` and `cancel` actions look up orders by ID without any ownership check, meaning any logged-in user can view or cancel another user's order simply by knowing or guessing its numeric ID (sequential integers starting from 1).

This is a textbook Broken Object Level Authorization vulnerability (OWASP API Security Top 10, #1). The data exposed includes confirmation numbers, payment references, full line-item breakdowns, and the ability to cancel a confirmed, paid order belonging to someone else.

---

## Issue #2 — SQL Injection in Event Search

**File:** `app/controllers/api/v1/events_controller.rb`
**Lines:** 10 (search), 21 (sort)
**Category:** Security
**Severity:** Critical

The `search` parameter is concatenated directly into a raw SQL string using Ruby string interpolation (`#{params[:search]}`), with no sanitization or parameterization. An attacker can close the string literal and append arbitrary SQL — bypassing the `published` scope to expose draft events, extracting data from other tables via `UNION`, or causing destructive side-effects. Line 21 passes `params[:sort_by]` directly into `.order()`, allowing unsanitized column names that enable schema enumeration through database error messages.

Both vectors are unauthenticated — no login is required to exploit them since `GET /events` is a public endpoint.

---

## Issue #3 — Event Ownership Never Verified on Mutations

**File:** `app/controllers/api/v1/events_controller.rb`
**Lines:** 89–96 (`update`), 99–103 (`destroy`)
**Category:** Security
**Severity:** Critical

The `update` and `destroy` actions find an event by ID and immediately act on it — there is no check that `current_user` is the event's organizer. Any authenticated user, including an `attendee`, can edit the title, venue, capacity, and status of any event, or delete it entirely. The ticket tier mutations in `ticket_tiers_controller.rb` (lines 23–48) have the same gap: `create`, `update`, and `destroy` never verify that the parent event belongs to the requester.

---

## Issue #4 — Ticket Inventory Race Condition (Oversell)

**File:** `app/models/ticket_tier.rb`
**Lines:** 17–24 (`reserve_tickets!`)
**Category:** Data Integrity
**Severity:** Critical

`reserve_tickets!` reads `available_quantity`, checks whether it covers the requested count, then increments `sold_count` — three separate, unlocked operations. Under concurrent load, two requests can both read `available_quantity = 1`, both pass the check independently, and both write `sold_count + 1`, resulting in more tickets sold than exist. This is a classic TOCTOU (Time-Of-Check-Time-Of-Use) race condition that will occur whenever two users attempt to buy the last ticket simultaneously.

The impact is direct financial and operational damage: an oversold event, angry attendees with valid confirmation numbers who cannot be admitted, and no automated detection of the inconsistency.

---

## Issue #5 — `sold_count` Is Mass-Assignable via API

**File:** `app/controllers/api/v1/ticket_tiers_controller.rb`
**Line:** 53 (`tier_params`)
**Category:** Security / Data Integrity
**Severity:** High

`sold_count` is included in the permitted parameters for ticket tier create and update. This field is the system's inventory counter — it is supposed to be mutated only by `reserve_tickets!` as tickets are purchased. Any authenticated user can send `sold_count: 200` in a `PUT` request to mark a tier as fully sold without a single ticket being purchased, or set it to a negative number to fraudulently manufacture artificial availability.

---

## Issue #6 — No State Machine: Invalid Order and Payment Transitions Allowed

**File:** `app/models/order.rb` lines 21–27 · `app/models/payment.rb` lines 7–14
**Category:** Architecture
**Severity:** High

Order status is a plain string field with only an `inclusion` validator — there are no transition guards. A `cancelled` order can be `confirmed`, a `refunded` order can go back to `pending`, and `payment.process!` can be called multiple times on the same payment (each call re-runs the random success logic, potentially confirming an already-confirmed order a second time and firing duplicate confirmation emails). The `aasm` gem is already present in the Gemfile but is not wired up anywhere.

---

## Issue #7 — No Foreign Key Constraints or Indexes on Any Relation

**Files:** `db/migrate/20241215000002` through `20241215000006`
**Category:** Performance / Data Integrity
**Severity:** High

Every foreign key column (`events.user_id`, `orders.user_id`, `orders.event_id`, `order_items.order_id`, `order_items.ticket_tier_id`, `ticket_tiers.event_id`, `payments.order_id`) is a plain `bigint` column with no `add_foreign_key` constraint and no index. The only index in the schema is the unique constraint on `users.email`. Without FK constraints, a raw SQL `DELETE` can silently orphan child records (e.g., payments with no parent order). Without indexes, every query that filters or joins on these columns performs a full sequential table scan — including the critical paths: loading a user's orders, finding all tiers for an event, and looking up a payment by order.
