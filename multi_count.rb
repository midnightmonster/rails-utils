# Copyright 2021 Joshua Paine
# 
# Permission to use, copy, modify, and/or distribute this software for any 
# purpose with or without fee is hereby granted.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY 
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, 
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM 
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR 
# PERFORMANCE OF THIS SOFTWARE.

module MultiCount
  # For including in your ApplicationRecord < ActiveRecord::Model
  extend ActiveSupport::Concern

  class_methods do
    def multi_count(*scopes, group_by: nil, **symbol_keyed_scopes)
      # Call with an array of scopes, get an array of counts back. Call with a 
      # hash of scopes, get a hash of counts back.
      # 
      # Use whenever you need seprate counts of records matching 2 to 10* scopes
      # when all the scopes require a scan of the same rows. I.e., they can't use
      # indexes, or some common scope is the part that uses the indexes.
      #
      # How it works:
      # For counting queries that don't use indexes, or after PG has used all the 
      # indexes that it can, typically 90%+ of the execution time is just getting 
      # to the data. Once PG is looking at a row, it makes very little difference
      # if you ask one question or half a dozen about the row. So this figures out 
      # what each scope would put in the "WHERE" portion of the query and instead
      # groups by all of those scope-WHEREs and gets the count. Then back in Ruby,
      # sum the results for each scope.
      #
      # Array invocation:
      #
      # sold_out, popular, on_sale = Store.find(id).products.multi_count(:sold_out,:popular,:on_sale)
      #
      # Hash invocation with non-boolean-value 'mfg_id' key:
      #
      # counts = Store.find(id).products.multi_count({
      #   'mfg_id' => Arel.sql('mfg_id'), # equivalent to .group(:mfg_id).count, e.g., {id=>count,...}
      #   'total'  => [:where,'true'],    # integer count as usual
      #   'on_sale'=> :on_sale,           # integer count as usual
      # })
      #
      # Depending on details, you get all the counts in ~ the time of a getting 
      # one or somewhere between the time of one and two counts. Due to (I assume)
      # query planner mysteries, it's often slightly faster to get multiple counts
      # than it is to get a single one.
      #
      # Caveat:
      # multi_count figures out for a given count whether you wanted a single 
      # count or a count-of-values hash by looking at what actually comes back.
      # If there are no rows at all, or the only value is null, multi_count won't
      # know you wanted a hash and will just give you a 0.
      #
      # *Start being careful at 10 scopes, because logical max rows returned from
      # the internal query this generates is 2^scopes-count for boolean scopes. 
      # In practice it's usually a lot fewer and the rows are only a few bytes 
      # each, though, so you can probably go higher. OTOH, you could get in 
      # trouble with fewer scopes if you use Arel.sql('string') scopes that return
      # many values like 'types' in the @counts example above.

      # WARNING
      # Ruby's flexible args are tricky tricky tricky. multi_count({a: 1, "b"=>2})
      # turns into multi_count({"b"=>2},,{a:1}). multi_count will do the right thing
      # as far as possible, but if you need to control the order of the hash output,
      # either keep all your keys the same type or call multi_count([{a:1, "b"=>2}])
      keyed_scopes = symbol_keyed_scopes.presence || {}
      keyed_scopes.merge! scopes[0] if 1==scopes.length && scopes[0].is_a?(Hash)
      keys, scopes = keyed_scopes.present? ? [keyed_scopes.keys, keyed_scopes.values] : [nil, scopes]
      # Numbered comment injection below exists to trick ActiveRecord into generating
      # unique aliases for each result column. ActiveRecord column aliases are a
      # truncatated naive transformation of the result column's SQL, and if two counts
      # are prefixed by a common (longish) filter, without the comments they will get 
      # the same alias and one will clobber the other.
      result_columns = scopes.each_with_index.map {|scope,i| "/*c#{i}*/ #{scope_to_result_column(scope)}" }
      result_columns << group_by.to_s unless group_by.nil?
      result_rows = all.group(result_columns).count('*')
      iterable_rows = group_by.nil? ? (result_rows.presence || {(scopes.length.times.map {nil})=>0}) : result_rows
      grouped_counts = iterable_rows.each_with_object({}) do |(match_pattern,count),grouped_result|
        key = match_pattern.pop unless group_by.nil?
        result = grouped_result[key] ||= scopes.length.times.map { Hash.new(0) }
        match_pattern.each_with_index {|match,i| result[i][match] += count }
      end.transform_values! do |counts|
        counts.map! do |column_counts|
          (column_counts.keys - [true,false,nil]).empty? ? column_counts[true] : column_counts
        end
        keys ? keys.zip(counts).to_h : counts
      end
      group_by ? grouped_counts : grouped_counts[nil]
    end

    private
    def scope_to_result_column(scope)
      # accept Arel.sql('SQL literal'), currently the only way to count distinct values, not just trues
      return scope if scope.is_a?(Arel::Nodes::SqlLiteral)
      # accept ActiveRecord::Relation for complicated constructed queries or (finally)...
      # accept the normal case, a simple scope or anything that could be passed to Relation.send
      relation = scope.is_a?(ActiveRecord::Relation) ? scope : unscoped.send(*Array(scope))
      relation.only(:where).to_sql.partition(' WHERE ').last
    end
  end
end