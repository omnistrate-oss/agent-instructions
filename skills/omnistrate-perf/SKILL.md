---
name: Optimizing List API Performance
description: Systematically identify and fix performance bottlenecks in Omnistrate list/fleet APIs. Analyzes query patterns, eliminates N+1 problems, adds bulk data access methods, introduces conditional loading via query parameters, and validates with unit tests. Works across api-design, commons, and service-orchestration repos.
---

# Optimizing List API Performance

## When to Use This Skill
- List APIs are slow when returning hundreds or thousands of items
- API response times degrade linearly with result count
- Database query count scales with result count (N+1 pattern)
- API returns data the caller doesn't need
- Fleet or inventory endpoints need performance optimization

## Architecture Context

Omnistrate list APIs follow a 3-repo pattern:

```
api-design          → API contract (Goa DSL, query params, response types)
    ↓
commons             → Data access layer (DAOs, GORM models, DB indices)
    ↓
service-orchestration → Handler logic (fetching, enrichment, response assembly)
```

Changes typically span all 3 repos. The dependency chain is: `service-orchestration` → `commons` → `api-design`. Merge order matters: api-design first, then commons, then service-orchestration.

## Optimization Workflow

### Phase 1: Profile the Current Implementation

**Goal**: Understand the exact query pattern and data flow.

1. **Trace the request path** from API spec → handler → data access:
   - Find the Goa DSL method in `api-design/v1/design/fleet/`
   - Find the handler in `service-orchestration/pkg/fleet/inventory/`
   - Identify all DAO calls made per request

2. **Count queries per response item**. For each item in the list:
   - How many DB queries are made?
   - Are any queries inside a `for` loop? (N+1 pattern)
   - Are queries sequential that could be parallel?

3. **Map the data flow**:
   - Which response fields come from which DB tables?
   - Which fields require joins or secondary lookups?
   - Which fields are actually used by callers (check UI code in `omnistrate-cloud-ui`)?

**Output**: A query profile showing total DB queries as a function of N (result count).

```
Example profile:
  N=1:    7 queries  (1 list + 1 service + 5 per-item enrichment)
  N=100:  502 queries (1 list + 1 service + 5*100 enrichment)
  N=1000: 5002 queries ← PROBLEM
```

### Phase 2: Design Bulk Data Access Methods

**Goal**: Replace per-item queries with bulk queries that fetch data for ALL items at once.

1. **Identify per-item queries** from Phase 1. Common patterns:
   - Count queries (user count, instance count per subscription)
   - Lookup queries (pricing, audit logs per subscription)
   - Aggregation queries (first usage time, last activity)

2. **Create bulk DAO methods** in `commons/pkg/dataaccess/`:
   - Naming convention: `Bulk{Operation}With Transaction`
   - Accept a slice of IDs, return a map keyed by ID
   - Use `WHERE id IN (?)` with GORM's placeholder expansion
   - Return `map[string]ResultType` for O(1) lookup per item

3. **Add corresponding interface methods** to the data access interfaces in `commons/pkg/dataaccess/interfaces/`

4. **Add stub implementations** in `commons/pkg/dataaccess/stubs/` for testing

**Bulk Method Pattern**:
```go
// Interface
BulkCountUsersBySubscriptionIDsWithTransaction(tx *gorm.DB, subscriptionIDs []string) (map[string]int64, error)

// Implementation
func (da *SubscriptionDataAccess) BulkCountUsersBySubscriptionIDsWithTransaction(
    tx *gorm.DB, subscriptionIDs []string,
) (map[string]int64, error) {
    if len(subscriptionIDs) == 0 {
        return make(map[string]int64), nil
    }
    type result struct {
        SubscriptionID string
        Count          int64
    }
    var results []result
    err := tx.Table("subscription_users").
        Select("subscription_id, COUNT(*) as count").
        Where("subscription_id IN ?", subscriptionIDs).
        Where("deleted_at = 0").
        Group("subscription_id").
        Find(&results).Error
    if err != nil {
        return nil, err
    }
    m := make(map[string]int64, len(results))
    for _, r := range results {
        m[r.SubscriptionID] = r.Count
    }
    return m, nil
}
```

**CRITICAL**: Always handle empty slice input — return early with empty map to avoid `WHERE IN ()` SQL errors.

### Phase 3: Add Conditional Loading Query Parameters

**Goal**: Let callers skip expensive data they don't need.

1. **Identify field groups** by cost and usage:
   - **Pricing**: billing details, scheduled pricing, audit logs (expensive: multiple JOINs + sorting)
   - **Stats**: user counts, instance counts, first usage time (expensive: COUNT aggregations)
   - **Core**: subscription metadata, status, product tier (cheap: already loaded)

2. **Add boolean query parameters** to the API spec in `api-design`:
   - `excludePricing` — skip billing/pricing data
   - `excludeStats` — skip count/aggregation data
   - Use `goa.Attribute()` in the payload type AND `goa.Param()` in the HTTP method

3. **Wire parameters** through the handler to conditionally skip bulk fetches

**API Design Pattern** (Goa DSL):
```go
// In the Payload type definition
goa.Attribute("excludePricing", goa.Boolean, "Exclude pricing details from response", func() {
    goa.Default(false)
})
goa.Attribute("excludeStats", goa.Boolean, "Exclude usage statistics from response", func() {
    goa.Default(false)
})

// In the HTTP method definition
goa.Param("excludePricing")
goa.Param("excludeStats")
```

**IMPORTANT**: Both `goa.Attribute()` AND `goa.Param()` are required. The attribute defines the field on the request struct; the param maps it to a query parameter. Missing either causes silent failures.

### Phase 4: Parallelize Bulk Pre-fetches

**Goal**: Run independent bulk queries concurrently to minimize wall-clock time.

1. **Use `sync.WaitGroup`** to run bulk queries in parallel
2. **Store results in a shared struct** with dedicated fields per goroutine (no mutex needed)
3. **Check errors after `wg.Wait()`** — any goroutine error fails the request
4. **Initialize nil maps to empty maps** after the wait to avoid nil-map panics downstream

**Parallel Pre-fetch Pattern**:
```go
type bulkResults struct {
    pricingMap      map[string][]PricingType
    userCountsMap   map[string]int64
    instanceCounts  map[string]int64
    pricingErr      error
    userCountErr    error
    instanceErr     error
}

var br bulkResults
var wg sync.WaitGroup

if !excludePricing {
    wg.Add(1)
    go func() {
        defer wg.Done()
        br.pricingMap, br.pricingErr = dao.BulkFindPricing(db, itemIDs)
    }()
}

if !excludeStats {
    wg.Add(2)
    go func() {
        defer wg.Done()
        br.userCountsMap, br.userCountErr = dao.BulkCountUsers(db, itemIDs)
    }()
    go func() {
        defer wg.Done()
        br.instanceCounts, br.instanceErr = dao.BulkCountInstances(db, serviceID, itemIDs)
    }()
}

wg.Wait()

// Check errors
if br.pricingErr != nil { return handleError(br.pricingErr) }
if br.userCountErr != nil { return handleError(br.userCountErr) }
// ...

// Nil-safe maps for downstream lookups
if br.pricingMap == nil { br.pricingMap = make(map[string][]PricingType) }
if br.userCountsMap == nil { br.userCountsMap = make(map[string]int64) }
```

### Phase 5: Refactor the Enrichment Function

**Goal**: Make the per-item enrichment function a pure function that only does map lookups.

1. **Extract enrichment into a package-level function** (not a method on the handler struct)
2. **Pass ALL data as parameters** — pre-built maps from Phase 4
3. **No DB calls inside the function** — every lookup is O(1) map access
4. **Respect exclude flags** — skip field population when excluded

**Pure Enrichment Function Pattern**:
```go
// Package-level function — no receiver, no DB access, no I/O
func describeItem(
    item ItemType,
    relatedDataMap map[string]RelatedType,
    countsMap map[string]int64,
    excludePricing bool,
    excludeStats bool,
) (*ResponseType, error) {
    res := &ResponseType{
        ID:     item.ID,
        Name:   item.Name,
        Status: item.Status,
    }

    if !excludeStats {
        res.Count = countsMap[item.ID]  // O(1) map lookup
    }

    if !excludePricing {
        pricing := relatedDataMap[item.ID]  // O(1) map lookup
        res.Pricing = formatPricing(pricing)
    }

    return res, nil
}
```

### Phase 6: Review Database Indices

**Goal**: Ensure bulk queries hit indices efficiently.

1. **Check existing GORM model tags** for index definitions
2. **Add indices for bulk query patterns**:
   - Composite indices matching `WHERE` + `GROUP BY` columns
   - Partial indices with `WHERE deleted_at = 0` for active-record queries
   - Covering indices that include all `SELECT` columns to avoid table lookups

3. **For indices that GORM tags can't express** (partial indices, cross-model columns), use raw SQL in automigration:

```go
tx = db.Exec(`
    CREATE INDEX IF NOT EXISTS idx_instances_service_subscription
    ON cluster.instances (service_id, subscription_id)
    WHERE deleted_at = 0;
`)
```

**When to use raw SQL vs GORM tags**:
- GORM tags: simple single/composite indices on model's own columns
- Raw SQL: partial indices (`WHERE` clause), indices on inherited/embedded columns, cross-schema indices

### Phase 7: Add Unit Tests

**Goal**: Comprehensive test coverage for the pure enrichment function and handler logic.

1. **Test the pure enrichment function extensively** — it's the primary test target since it has no I/O:
   - Basic field mapping
   - Edge cases (deleted users, nil maps, zero counts)
   - Exclude flag combinations
   - Pricing logic (active/expired/future/soft-deleted/multiple)
   - Audit log ordering

2. **Test the handler with mocked data access**:
   - Use stubs from `commons/pkg/dataaccess/stubs/`
   - Set `On*` callback fields to control stub behavior
   - Construct the handler struct directly (don't use constructor)

3. **CRITICAL: Set default no-op callbacks** for all bulk methods in the test helper to avoid mock panics from goroutines:

```go
func newTestHandler() (Handler, *stubs.DataAccessStub) {
    da := stubs.NewDataAccessStub()
    // Default no-op callbacks prevent mock panics in goroutines
    da.OnBulkMethod1 = func(_ *gorm.DB, _ []string) (map[string]int64, error) {
        return nil, nil
    }
    da.OnBulkMethod2 = func(_ *gorm.DB, _ []string) ([]ResultType, error) {
        return nil, nil
    }
    // ... set ALL bulk callbacks
    return Handler{db: &gorm.DB{Statement: &gorm.Statement{}}, da: da}, da
}
```

4. **Test categories**:
   - Input validation (empty IDs, missing params)
   - Access control (RBAC forbidden)
   - Empty results
   - Normal results with data
   - Exclude flag behavior (verify bulk methods are NOT called)
   - Error propagation from bulk methods
   - Filtering logic (product tier, include inactive)

### Phase 8: Create PRs and Merge

**Goal**: Ship changes across all 3 repos in dependency order.

1. **api-design PR** (merge first):
   - New query parameters in Goa DSL
   - Run `make generate` to regenerate code
   - CI must pass before merge

2. **commons PR** (merge second):
   - New bulk DAO methods + interfaces + stubs
   - New database indices
   - Integration tests for bulk methods
   - Depends on api-design being merged (for type definitions)

3. **service-orchestration PR** (merge last):
   - Handler refactoring with parallel pre-fetches
   - Pure enrichment function
   - Unit tests
   - Update `go.mod` to point to merged api-design and commons versions

**Dependency update pattern**:
```bash
# After api-design merges and tags (e.g., v0.23.0)
go get github.com/omnistrate/api-design/v1@v0.23.0
# After commons merges and tags (e.g., v1.24.0)
go get github.com/omnistrate/commons@v1.24.0
go mod tidy
```

## Critical Rules

- **NEVER** put DB queries inside a `for` loop over list results — this is the N+1 anti-pattern
- **ALWAYS** handle empty ID slices in bulk methods — `WHERE IN ()` is invalid SQL
- **ALWAYS** initialize nil maps to empty maps before downstream map lookups
- **ALWAYS** set default no-op callbacks on ALL stub bulk methods in tests to prevent goroutine panics
- **ALWAYS** use `sync.WaitGroup` (not goroutine-per-item) for bulk pre-fetches
- **NEVER** use mutexes for the parallel pre-fetch pattern — each goroutine writes to its own struct field
- **ALWAYS** merge PRs in dependency order: api-design → commons → service-orchestration
- **ALWAYS** add both `goa.Attribute()` AND `goa.Param()` for new query parameters
- **ALWAYS** write the enrichment function as a package-level pure function (no receiver, no DB)

## Performance Targets

| Metric | Before | After |
|--------|--------|-------|
| DB queries for N items | 2 + 5N | ~10 (constant) |
| Wall-clock time scaling | O(N) | O(1) for queries, O(N) for assembly |
| Unnecessary data loaded | 100% of fields | Only requested field groups |

## Success Criteria

- ✅ Query count is constant regardless of result count (no N+1)
- ✅ Bulk methods tested with 1000+ IDs
- ✅ Exclude params skip their respective bulk fetches entirely
- ✅ Pure enrichment function has 20+ test cases covering edge cases
- ✅ Handler tests verify exclude flags, error propagation, and filtering
- ✅ All database indices support the new bulk query patterns
- ✅ CI passes on all 3 PRs
- ✅ PRs merged in correct dependency order

## Reference
See LIST_API_PERFORMANCE_REFERENCE.md for:
- Complete database index design guidelines
- Bulk method implementation templates
- Test patterns with stubs
- Query profiling techniques
- Real-world example (ListSubscription optimization)
