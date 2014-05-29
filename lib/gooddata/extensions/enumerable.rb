module Enumerable
  def mapcat(initial = [], &block)
    reduce(initial) do |a, e|
      a.concat(block.call(e))
      a
    end
  end
end