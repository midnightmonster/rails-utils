# Rails Utilities

Except for MultiCount, these could be useful with any Ruby project, but realistically, it's probably Rails.

## MultiCount

Are you sending multiple queries to get different counts or summaries of the same rows of data? Is Postgres giving you side-eye because you ask it to visit the same records several times in one controller action? `MultiCount` is here for you. `include MultiCount` in your `ApplicationModel` and replace those 2-10 queries with smart, fast one.

## CountVonCount

You're using `find_each` to avoid instantiating thousands of records at once, but are you really releasing those records or accidentally holding on to them? Use `CountVonCount` to audit just what Ruby's allocating and garbage collecting.

## Snowdrift

Explicitly and conveniently accumulate and report on counts, lists, and sets over multi-step processes, even with nested levels of consideration. (E.g., while processing inventory reports, track available widgets by store, region, and globally.)
