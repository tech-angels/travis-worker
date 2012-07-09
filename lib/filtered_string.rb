class FilteredString < Struct.new(:unfiltered, :filtered)
  def to_s
    filtered
  end

  def to_str
    to_s
  end

  def mutate(*args)
    str = args.shift
    filtered = str % args
    unfiltered = str % args.map { |v| v.respond_to?(:unfiltered) ? v.unfiltered : v }

    FilteredString.new(unfiltered, filtered)
  end
end
