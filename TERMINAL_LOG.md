# EventNest — Terminal Log

**Purpose:** Live proof of critical vulnerabilities identified in REVIEW.md
**Pre-requisite:** App running at `http://localhost:3000` with seed data loaded

---

## Demo 1 — Broken Object-Level Authorization on Orders (Issue #1)

We are logging in as **Vikram Patel** (`vikram@example.com`), an attendee who has placed exactly one order in the system — a RailsConf India ticket worth ₹4,999. After authenticating as Vikram, we hit the orders endpoint. The expectation is that Vikram should only see his own order. What actually comes back is every order in the database — including orders belonging to Ananya and Sneha, users Vikram has no relation to.

### Step 1 — Login as Vikram

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"vikram@example.com","password":"password123"}'
```

### Step 2 — Fetch orders using Vikram's token

Replace `VIKRAM_TOKEN` with the token returned above.

```bash
curl -s http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer VIKRAM_TOKEN"
```

**Expected:** 1 order (Vikram's own).
**Actual:** All 4 orders in the system — Ananya's music festival booking, Vikram's conference ticket, Sneha's workshop seat, and Ananya's cancelled order — fully exposed to a user who should only see his own data.

---

## Demo 2 — SQL Injection in Event Search (Issue #2)

The events search endpoint builds its SQL query by directly interpolating the `search` parameter into a raw string — no parameterization, no sanitization. We demonstrate this in two steps: first a clean search to establish the baseline, then the same search with an injected payload to show the query is being manipulated.

This endpoint is fully public — no login or token is required.

### Before — Normal search (baseline)

Searching for `railsconf` returns exactly one event: the RailsConf India conference.

```bash
curl -s "http://localhost:3000/api/v1/events?search=railsconf"
```

**Expected:** 1 result — RailsConf India 2025.
**Actual:** 1 result — behaves correctly under normal input.

### After — Same search with SQL injection payload

The payload `railsconf' OR title LIKE '` closes the SQL string early and appends an always-true condition, making the search term meaningless.

```bash
curl -s "http://localhost:3000/api/v1/events?search=railsconf%27%20OR%20title%20LIKE%20%27"
```

**Expected:** 1 result — RailsConf India 2025 (same as above).
**Actual:** All 3 published events are returned — the music festival and PostgreSQL workshop appear alongside RailsConf, despite having no relation to the search term. The injected SQL has overridden the search filter entirely.

---

## Demo 3 — Bookmark Feature (Task 3)

We demonstrate the full bookmark flow using **Ananya Gupta** (`ananya@example.com`), an attendee from the seed data. The steps cover the happy path (create a bookmark), the duplicate rejection, and listing the user's bookmarks.

**Pre-requisite:** Run the bookmark migration against the development database before starting.

```bash
docker compose exec web rails db:migrate
```

---

### Step 1 — Login as Ananya (attendee) and grab the token

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"ananya@example.com","password":"password123"}'
```

Copy the `token` value from the response. Replace `ANANYA_TOKEN` with it in all steps below.

---

### Step 2 — Bookmark an event (happy path)

Ananya bookmarks Event #1 — Mumbai Indie Music Festival.

```bash
curl -s -X POST http://localhost:3000/api/v1/events/1/bookmarks \
  -H "Authorization: Bearer ANANYA_TOKEN"
```

**Expected:** `201 Created` with a bookmark ID and confirmation message.

---

### Step 3 — Attempt to bookmark the same event again (duplicate rejection)

Sending the exact same request a second time hits the uniqueness constraint.

```bash
curl -s -X POST http://localhost:3000/api/v1/events/1/bookmarks \
  -H "Authorization: Bearer ANANYA_TOKEN"
```

**Expected:** `422 Unprocessable Entity` with the error `"You have already bookmarked this event"`. No duplicate record is created.

---

### Step 4 — View Ananya's bookmark list

```bash
curl -s http://localhost:3000/api/v1/bookmarks \
  -H "Authorization: Bearer ANANYA_TOKEN"
```

**Expected:** `200 OK` with a list containing only Ananya's bookmarked events — event title, city, start time, and when it was bookmarked.
