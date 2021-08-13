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

class Snowdrift
  def initialize
    @drifts = []
  end

  def self.accumulate(hash_of_initial_values)
    # If you're going to pass the accumulator around or only use it locally, you
    # don't need to save an instance.
    self.new(hash_of_initial_values).accumulate {|drift| yield drift }
  end

  def accumulate(hash_of_initial_values)
    # Create a new 'drift' to accumulate values according to the hash you pass in.
    # You can call accumulate inside an accumulate block, and any keys that also
    # exist in a parent block will mask the parent's value for return-from-update
    # purposes, but all drifts with the key will be updated, and you can mix keys 
    # from different levels freely.
    # Returns a dup of your hash with whatever changes to the values you've made.
    @drifts.push(hash_of_initial_values.dup)
    yield self
    @drifts.pop
  end

  def incr(*args)
    # Increment the stored value for every key in *args.
    # Returns array of new values in order of arguments
    args.map do |key|
      update(key) {|v| v+1 }
    end
  end

  def add(hash)
    # For every key=>value in hash, add value to key.
    # Returns matching hash of new values
    hash.each_with_object({}) do |(key,addend),obj|
      # Ok to pass nil or (improbably) false: we'll just return the existing value
      obj[key] = update(key) {|v| addend ? v + addend : v }
    end
  end

  def update(key)
    # Updates all drifts that have this key by yielding the existing value to the block.
    # Raises if no drifts have this key.
    # Returns new value according to the closest drift that has the key.
    had_key = false
    result = nil
    @drifts.each do |hash|
      next unless hash.has_key? key
      had_key = true
      hash[key] = result = yield hash[key]
    end
    raise "Can't update key #{key.inspect} which isn't being accumulated." unless had_key
    result
  end

end
