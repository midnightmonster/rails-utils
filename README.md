# Rails Utilities

## MultiCount

Are you sending multiple queries to get different counts or summaries of the same rows of data? Is Postgres giving you side-eye because you ask it to visit the same records several times in one controller action? `MultiCount` is here for you. `include MultiCount` in your `ApplicationModel` and replace those 2-10 queries with one smart, fast query.

```ruby
# Assuming foo and bar are Widget scopes...

widgets = factory.widgets.available
foo_count = widgets.foo.count
bar_count = widgets.bar(zonk).count
spin_counts = widgets.group(:spin).count

# ...becomes...

foo_count, bar_count, spin_counts = 
  factory.widgets.available.multi_count(
    :foo,
    [:bar,zonk],
    Arel.sql('widgets.spin')
  )

# ...which runs a single query that in most cases is no slower than the
# slowest of the original three. Sometimes it's actually faster, due to
# Query Planner Mysteries.
```

## CountVonCount

You're using `find_each` to avoid instantiating thousands of records at once, but are you really releasing those records or accidentally holding on to them? Use `CountVonCount` to audit exactly what Ruby's allocating and garbage collecting.

## Snowdrift

Explicitly and conveniently accumulate and report on counts, lists, and sets over multi-step processes, even with nested levels of consideration. (E.g., while processing inventory reports, track available widgets by store, region, and globally.) `Snowdrift` is not specific to Rails/ActiveRecord and could be used in any Ruby application.
