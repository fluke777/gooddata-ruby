module Enumerable
  def mapcat(initial = [], &block)
    reduce(initial) do |a, e|
      block.call(e).each do |x|
        a << x
      end
      a
    end
  end

  def rjust(n, x)
    Array.new([0, n-length].max, x) + self
  end

  def ljust(n, x)
    dup.fill(x, length...n)
  end
end
