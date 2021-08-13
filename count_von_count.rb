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

# Track allocation and garbage collection of specified ActiveRecord model 
# objects within a block. E.g., in the block below, do anything that allocates
# Users and Items.
#
# Optionally call cvc.checkpoint("optional label") to add a line to the report.
#
# Try with and without throwing in `GC.start`. The difference between what ruby
# _could_ garbage collect and what it normally _does_ may surprise you.
#
#   CountVonCount.count(User,Item) do |cvc|
#     cvc.report # return cvc.report from the block or save it some other way so you can read it
#   end

class CountVonCount
  Stats = Struct.new(:type, :note, :live, :count, :max, :initialized, :collected, :elapsed) do
    def checkpoint(note,start)
      # called on the one true stats obj per type, generates point-in-time records
      out = dup
      out.note = note
      out.count = @audit ? ObjectSpace.each_object(type).count : live
      out.elapsed = Time.now - start
      out
    end
    def report(for_class=nil)
      # called on the point-in-time records for display/reading at the end
      return nil unless for_class.nil? || for_class==type
      out = to_h
      out[:type] = type.name
      out.delete :count unless @audit
      out.delete :type if for_class
      out.delete :note unless for_class
      out
    end
    def audit!
      @audit = true
    end
  end
  
  def self.count(*classes)
    cvc = new(*classes)
    begin 
      out = yield cvc
    ensure
      cvc.cleanup
    end
    out
  end
  
  def initialize(*classes)
    @classes = classes
    @report = []
    @stats = {}
    classes.uniq.each do |klass|
      klass.send :define_method, method_name_for(klass), setup_callback_for(klass)
      klass.send :set_callback, :initialize, :after, method_name_for(klass)
    end
    @start = Time.now
    checkpoint "Start!"
  end

  def audit!
    # Call as soon as you open the block to perform additional counting at each checkpoint.
    # Only useful if you suspect record-keeping bugs in CountVonCount.
    @stats.values.each &:audit!
  end

  def checkpoint(note=nil, save: true)
    entry = @stats.values.map {|stats| stats.checkpoint(note,@start) }
    @report.push(entry) if save
    entry
  end
  
  def report(for_class=nil)
    return @report.flatten.map {|s| s.report(for_class) }.compact if for_class
    lines = @report + [checkpoint("Report!",save: false)]
    lines.map {|cp| [cp[0].note] + cp.map(&:report) }
  end

  def cleanup
    @classes.each do |klass|
      klass.send :skip_callback, :initialize, :after, method_name_for(klass) # without condition args, skip_callback actually _removes_ callback
      klass.send :remove_method, method_name_for(klass)
      ObjectSpace.each_object(klass) do |model|
        ObjectSpace.undefine_finalizer(model)
      end
    end
  end

  private

    def method_name_for(klass)
      ("_cvc_init_"+klass.name.snakecase).to_sym
    end

    def setup_callback_for(klass)
      stats = @stats[klass.name] = Stats.new(klass,nil,0,0,0,0,0,0)
      goodbye = proc{|_| stats.collected += 1; stats.live -= 1 } # called on each object when garbage collected
      starting = ObjectSpace.each_object(klass) do |model|
        ObjectSpace.define_finalizer(model, goodbye)
      end # returns count
      stats[:live] = starting
      stats[:max]  = starting
      proc do
        stats[:live] += 1
        stats[:initialized] += 1
        stats[:max] = stats[:live] if stats[:live] > stats[:max]
        ObjectSpace.define_finalizer(self, goodbye)
      end
    end
end
