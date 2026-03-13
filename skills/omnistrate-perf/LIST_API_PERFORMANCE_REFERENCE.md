# List API Performance Optimization Reference

This document provides detailed reference information for optimizing Omnistrate list APIs. See SKILL.md for the main optimization workflow.

## Table of Contents
1. [Query Profiling Techniques](#query-profiling-techniques)
2. [Bulk Method Templates](#bulk-method-templates)
3. [Database Index Design](#database-index-design)
4. [Test Patterns with Stubs](#test-patterns-with-stubs)
5. [Real-World Example: ListSubscription](#real-world-example-listsubscription)
6. [Common List APIs to Optimize](#common-list-apis-to-optimize)

## Query Profiling Techniques

### Step 1: Trace the Handler

Find the handler method and count every DAO call:

```bash
# Find the handler file
grep -rn "func.*ListSubscription\|func.*ListInstances" service-orchestration/pkg/fleet/

# Count DAO calls inside the handler
grep -n "DataAccess\.\|dataAccess\." service-orchestration/pkg/fleet/inventory/subscription.go
```

### Step 2: Identify N+1 Patterns

Look for DAO calls inside loops:

```bash
# Find loops with DAO calls inside
grep -B5 -A5 "for.*range.*subscriptions\|for.*range.*instances" handler.go | grep -A5 "DataAccess"
```

### Step 3: Build a Query Profile Table

| Query | Per-Request | Per-Item | Total (N=500) |
|-------|------------|----------|---------------|
| FindSubscriptions | 1 | - | 1 |
| FindService | 1 | - | 1 |
| FindProductTier | - | 1 | 500 |
| CountUsers | - | 1 | 500 |
| CountInstances | - | 1 | 500 |
| FindFirstUsage | - | 1 | 500 |
| FindPricing | - | 1 | 500 |
| **Total** | **2** | **5** | **2,502** |

### Step 4: Verify with DB Logging

Enable GORM query logging temporarily:

```go
db.Session(&gorm.Session{Logger: logger.Default.LogMode(logger.Info)})
```

## Bulk Method Templates

### Template 1: Bulk Count (GROUP BY)

Returns `map[string]int64` — count per parent ID.

```go
// Interface
BulkCountItemsByParentIDsWithTransaction(tx *gorm.DB, parentIDs []string) (map[string]int64, error)

// Implementation
func (da *DataAccess) BulkCountItemsByParentIDsWithTransaction(
    tx *gorm.DB, parentIDs []string,
) (map[string]int64, error) {
    if len(parentIDs) == 0 {
        return make(map[string]int64), nil
    }

    type countResult struct {
        ParentID string `gorm:"column:parent_id"`
        Count    int64  `gorm:"column:count"`
    }

    var results []countResult
    err := tx.Table("items").
        Select("parent_id, COUNT(*) as count").
        Where("parent_id IN ?", parentIDs).
        Where("deleted_at = 0").
        Group("parent_id").
        Find(&results).Error

    if err != nil {
        return nil, errors.Wrap(err, "BulkCountItemsByParentIDs")
    }

    m := make(map[string]int64, len(results))
    for _, r := range results {
        m[r.ParentID] = r.Count
    }
    return m, nil
}
```

### Template 2: Bulk Aggregate (MIN/MAX per group)

Returns `map[string]time.Time` — aggregate per parent ID.

```go
// Interface
BulkFindFirstUsageTimesWithTransaction(tx *gorm.DB, parentIDs []string) (map[string]time.Time, error)

// Implementation
func (da *DataAccess) BulkFindFirstUsageTimesWithTransaction(
    tx *gorm.DB, parentIDs []string,
) (map[string]time.Time, error) {
    if len(parentIDs) == 0 {
        return make(map[string]time.Time), nil
    }

    type timeResult struct {
        ParentID  string    `gorm:"column:parent_id"`
        FirstTime time.Time `gorm:"column:first_time"`
    }

    var results []timeResult
    err := tx.Table("items").
        Select("parent_id, MIN(created_at) as first_time").
        Where("parent_id IN ?", parentIDs).
        Where("deleted_at = 0").
        Group("parent_id").
        Find(&results).Error

    if err != nil {
        return nil, errors.Wrap(err, "BulkFindFirstUsageTimes")
    }

    m := make(map[string]time.Time, len(results))
    for _, r := range results {
        m[r.ParentID] = r.FirstTime
    }
    return m, nil
}
```

### Template 3: Bulk Fetch Related Records

Returns `map[string][]RelatedType` — slice of related records per parent ID.

```go
// Interface
BulkFindRelatedByParentIDsWithTransaction(tx *gorm.DB, parentIDs []string) (map[string][]RelatedType, error)

// Implementation
func (da *DataAccess) BulkFindRelatedByParentIDsWithTransaction(
    tx *gorm.DB, parentIDs []string,
) (map[string][]RelatedType, error) {
    if len(parentIDs) == 0 {
        return make(map[string][]RelatedType), nil
    }

    var records []RelatedType
    err := tx.Table("related_items").
        Where("parent_id IN ?", parentIDs).
        Order("parent_id, start_time ASC").
        Find(&records).Error

    if err != nil {
        return nil, errors.Wrap(err, "BulkFindRelatedByParentIDs")
    }

    m := make(map[string][]RelatedType, len(parentIDs))
    for _, r := range records {
        m[r.ParentID] = append(m[r.ParentID], r)
    }
    return m, nil
}
```

### Template 4: Bulk Count with Composite Key

When the count requires filtering by an additional dimension (e.g., service_id + subscription_id):

```go
func (da *DataAccess) BulkCountInstancesBySubscriptionsWithTransaction(
    tx *gorm.DB, serviceID string, subscriptionIDs []string,
) (map[string]int64, error) {
    if len(subscriptionIDs) == 0 {
        return make(map[string]int64), nil
    }

    type countResult struct {
        SubscriptionID string `gorm:"column:subscription_id"`
        Count          int64  `gorm:"column:count"`
    }

    var results []countResult
    err := tx.Table("instances").
        Select("subscription_id, COUNT(*) as count").
        Where("service_id = ?", serviceID).
        Where("subscription_id IN ?", subscriptionIDs).
        Where("deleted_at = 0").
        Group("subscription_id").
        Find(&results).Error

    if err != nil {
        return nil, errors.Wrap(err, "BulkCountInstancesBySubscriptions")
    }

    m := make(map[string]int64, len(results))
    for _, r := range results {
        m[r.SubscriptionID] = r.Count
    }
    return m, nil
}
```

## Database Index Design

### Index Selection Criteria

For each bulk query, design an index that:
1. **Covers the WHERE clause** — all filtered columns as leading index columns
2. **Covers the GROUP BY** — grouping column should be in the index
3. **Supports the SELECT** — include selected columns for covering index (avoids table lookup)

### Index Types

#### Simple Composite Index (GORM tag)

Use when the index columns are on the model's own fields:

```go
type SubscriptionUser struct {
    SubscriptionID string `gorm:"index:idx_sub_users,priority:1"`
    UserID         string `gorm:"index:idx_sub_users,priority:2"`
    DeletedAt      soft_delete.DeletedAt `gorm:"index:idx_sub_users,priority:3"`
}
```

#### Partial Index (Raw SQL)

Use when you need a `WHERE` clause on the index — GORM tags don't support this:

```go
tx = db.Exec(`
    CREATE INDEX IF NOT EXISTS idx_instances_service_subscription
    ON cluster.instances (service_id, subscription_id)
    WHERE deleted_at = 0;
`)
```

Partial indices are smaller and faster because they only index rows matching the condition.

#### Cross-Model Column Index (Raw SQL)

Use when the column is defined in an embedded/inherited struct (like `ModelBaseDate.CreatedAt`):

```go
tx = db.Exec(`
    CREATE INDEX IF NOT EXISTS idx_instances_subscription_created
    ON cluster.instances (subscription_id, created_at);
`)
```

GORM auto-migration only creates indices from tags on the model itself, not embedded structs.

### Index Design for Common Bulk Queries

| Query Pattern | Index Design | Type |
|--------------|-------------|------|
| `COUNT(*) WHERE parent_id IN ? AND deleted_at = 0 GROUP BY parent_id` | `(parent_id) WHERE deleted_at = 0` | Partial |
| `MIN(created_at) WHERE parent_id IN ? GROUP BY parent_id` | `(parent_id, created_at)` | Composite |
| `SELECT * WHERE parent_id IN ? ORDER BY start_time` | `(parent_id, start_time)` | Composite |
| `COUNT(*) WHERE service_id = ? AND sub_id IN ? AND deleted_at = 0` | `(service_id, sub_id) WHERE deleted_at = 0` | Partial + Composite |

### Verifying Index Usage

```sql
EXPLAIN ANALYZE SELECT subscription_id, COUNT(*)
FROM cluster.instances
WHERE service_id = 'svc-123'
  AND subscription_id IN ('sub-1', 'sub-2', 'sub-3')
  AND deleted_at = 0
GROUP BY subscription_id;
```

Look for `Index Scan` or `Index Only Scan` — avoid `Seq Scan` on large tables.

## Test Patterns with Stubs

### Test Setup Helper

Always create a helper that initializes the handler with default no-op bulk callbacks:

```go
func newTestInventory() (Inventory, *stubs.SubscriptionDataAccessStub, *stubs.InstanceDataAccessStub) {
    subDA := stubs.NewSubscriptionDataAccessStub()
    instanceDA := stubs.NewInstanceDataAccessStub()

    // CRITICAL: Set default no-op callbacks for ALL bulk methods
    // Without these, goroutines will panic on unexpected mock calls
    subDA.OnBulkFindPricingWithTransaction = func(_ *gorm.DB, _ []string) ([]PricingType, error) {
        return nil, nil
    }
    subDA.OnBulkCountUsersWithTransaction = func(_ *gorm.DB, _ []string) (map[string]int64, error) {
        return nil, nil
    }
    instanceDA.OnBulkCountInstancesWithTransaction = func(_ *gorm.DB, _ string, _ []string) (map[string]int64, error) {
        return nil, nil
    }

    inv := Inventory{
        db:         &gorm.DB{Statement: &gorm.Statement{}},
        logger:     zap.NewNop(),
        subDA:      subDA,
        instanceDA: instanceDA,
    }
    return inv, subDA, instanceDA
}
```

**Why default callbacks are critical**: The parallel pre-fetch goroutines call bulk methods. If a test doesn't set a callback, the stub falls through to `mock.Mock.Called()`, which panics on unexpected calls. Since these run in goroutines, the panic crashes the test process.

### Test Categories

#### 1. Pure Enrichment Function Tests (highest value)

```go
func TestDescribeItem_BasicFields(t *testing.T) {
    t.Parallel()
    item := makeTestItem("item-1")
    relatedMap := map[string][]Related{"item-1": {makeRelated()}}
    countsMap := map[string]int64{"item-1": 5}

    res, err := describeItem(item, relatedMap, countsMap, false, false)

    require.NoError(t, err)
    assert.Equal(t, "item-1", res.ID)
    assert.Equal(t, int64(5), *res.Count)
}

func TestDescribeItem_ExcludeStats(t *testing.T) {
    t.Parallel()
    item := makeTestItem("item-1")

    res, err := describeItem(item, nil, nil, false, true) // excludeStats=true

    require.NoError(t, err)
    assert.Nil(t, res.Count)       // Stats excluded
    assert.NotNil(t, res.Pricing)  // Pricing still present
}
```

#### 2. Handler Tests (verify conditional loading)

```go
func TestListItems_ExcludePricingSkipsBulkFetch(t *testing.T) {
    t.Parallel()
    inv, subDA, _ := newTestInventory()

    pricingCalled := false
    subDA.OnBulkFindPricingWithTransaction = func(_ *gorm.DB, _ []string) ([]PricingType, error) {
        pricingCalled = true
        return nil, nil
    }

    // Setup: return 1 item, set excludePricing=true
    subDA.OnFindItems = func(...) ([]Item, error) {
        return []Item{makeTestItem("item-1")}, nil
    }

    _, err := inv.ListItems(ctx, &ListRequest{ExcludePricing: ptrBool(true)})

    require.NoError(t, err)
    assert.False(t, pricingCalled, "Pricing bulk fetch should be skipped")
}
```

#### 3. Error Propagation Tests

```go
func TestListItems_BulkPricingError(t *testing.T) {
    t.Parallel()
    inv, subDA, _ := newTestInventory()

    subDA.OnBulkFindPricingWithTransaction = func(_ *gorm.DB, _ []string) ([]PricingType, error) {
        return nil, fmt.Errorf("pricing DB error")
    }
    // Set up other callbacks to return successfully...

    _, err := inv.ListItems(ctx, &ListRequest{})

    assert.Error(t, err) // Don't check message — handleError sanitizes it
}
```

### Test Utilities

```go
func ptrStr(s string) *string    { return &s }
func ptrBool(b bool) *bool       { return &b }
func ptrInt64(n int64) *int64    { return &n }
func ptrTime(t time.Time) *time.Time { return &t }

func makeTestItem(id string) ItemType {
    return ItemType{
        ID:     id,
        Status: StatusActive,
    }
}
```

## Real-World Example: ListSubscription

### Before Optimization

```
Request: GET /fleet/service/{id}/environment/{id}/subscription

Per request:
  1× FindSubscriptionsForServiceEnvironment
  1× FindService

Per subscription (N+1):
  1× FindProductTier
  1× CountUsersForSubscription
  1× CountInstancesForSubscription  
  1× FindFirstUsageTime
  1× FindPricingWithPreload
  1× FindAuditLogs (sometimes)

Total for 500 subscriptions: ~2,502 queries
Response time: ~8-12 seconds
```

### After Optimization

```
Request: GET /fleet/service/{id}/environment/{id}/subscription
         ?excludePricing=true&excludeStats=false

Per request (constant):
  1× FindSubscriptionsForServiceEnvironment
  1× FindService
  N× FindProductTier (deduplicated by tier ID)
  N× GetUserOrgRole (deduplicated by user ID)

Parallel bulk pre-fetches (conditional):
  1× BulkCountUsers (if !excludeStats)
  1× BulkCountInstances (if !excludeStats)
  1× BulkFindFirstUsageTimes (if !excludeStats)
  1× BulkFindAllPricing (if !excludePricing)

Total for 500 subscriptions: ~10 queries
With excludePricing + excludeStats: ~6 queries
Response time: <500ms
```

### Files Changed

| Repo | File | Change |
|------|------|--------|
| api-design | `v1/design/fleet/subscription.go` | Added `excludePricing`, `excludeStats` query params |
| commons | `pkg/dataaccess/interfaces/subscription.go` | Added 3 bulk method interfaces |
| commons | `pkg/dataaccess/interfaces/instance.go` | Added 1 bulk method interface |
| commons | `pkg/dataaccess/subscription_data_access.go` | Implemented 3 bulk methods |
| commons | `pkg/dataaccess/instance_data_access.go` | Implemented 1 bulk method |
| commons | `pkg/dataaccess/stubs/subscriptiondataaccess_stub.go` | Added stub callbacks |
| commons | `pkg/dataaccess/stubs/instancedataaccess_stub.go` | Added stub callback |
| commons | `pkg/dataaccess/automigration.go` | Added 2 raw SQL indices |
| service-orch | `pkg/fleet/inventory/subscription.go` | Parallel pre-fetches, pure enrichment function |
| service-orch | `pkg/fleet/inventory/subscription_test.go` | 35 unit tests |

### PR Sequence

1. **api-design** — merge first, generates new request types with exclude params
2. **commons** — merge second, provides bulk DAO methods and indices
3. **service-orchestration** — merge last, uses both; update go.mod to point to tagged releases

## Common List APIs to Optimize

Use the query profiling technique from Phase 1 on these endpoints:

| API | Handler Location | Likely N+1 Pattern |
|-----|-----------------|-------------------|
| Fleet ListSubscription | `fleet/inventory/subscription.go` | ✅ Optimized |
| Fleet ListInstances | `fleet/inventory/instance.go` | Per-instance resource status lookups |
| Fleet ListServiceEnvironments | `fleet/inventory/environment.go` | Per-environment instance counts |
| Fleet ListDeploymentCells | `fleet/inventory/deployment_cell.go` | Per-cell health aggregation |
| ListServicePlans | `fleet/inventory/plan.go` | Per-plan pricing lookups |

### Optimization Priority Matrix

| Factor | Weight | How to Measure |
|--------|--------|---------------|
| Query count at scale | High | Profile at N=100, N=500, N=1000 |
| p99 response time | High | Check monitoring dashboards |
| Call frequency | Medium | Check API access logs |
| Data size per response | Medium | Measure JSON response bytes |
| Caller needs | Medium | Check which fields the UI actually uses |

Prioritize APIs that are: called frequently + have high N + return unused data.
