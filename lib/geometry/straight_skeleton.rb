module StraightSkeleton
  DEFAULT_ROUNDING_ANGLE = 15
  
  module Node
    attr_reader :point, :travel, :neighbours, :headings, :whence, :original
    attr_writer :collapsed
    
    def active?
      @nodes.include? self
    end
    
    def terminal?
      @neighbours.one?
    end
    
    def prev
      @neighbours[0]
    end
    
    def next
      @neighbours[1]
    end
    
    def heading
      @heading ||= headings.compact.inject do |heading1, heading2|
        sum = heading1.plus heading2
        sum.all?(&:zero?) ? heading1.perp : sum.normalised
      end
    end
    
    def secant
      @secant ||= 1.0 / headings.compact.first.dot(heading)
    end
    
    def collapses
      @neighbours.map.with_index do |neighbour, index|
        next unless neighbour
        next if neighbour.point.equal? @point
        cos = Math::cos(neighbour.heading.angle - heading.angle)
        next if cos*cos == 1.0
        distance = neighbour.heading.times(cos).minus(heading).dot(@point.minus neighbour.point) / (1.0 - cos*cos)
        next if distance.nan?
        travel = @travel + distance / secant
        next if travel < @travel || travel < neighbour.travel
        Collapse.new @nodes, heading.times(distance).plus(@point), travel, [ neighbour, self ].rotate(index)
      end.compact
    end
    
    def current
      active? ? self : @collapsed ? @collapsed.current : nil
    end
  end
  
  module InteriorNode
    include Node
    
    def <=>(other)
      @travel <=> other.travel
    end
    
    def insert!
      @headings = @neighbours.map.with_index do |neighbour, index|
        neighbour.neighbours[1-index] = self if neighbour
        neighbour.headings[1-index] if neighbour
      end
      @nodes.insert self
    end
  end
  
  class Collapse
    include InteriorNode
    
    def initialize(nodes, point, travel, sources)
      @original, @nodes, @point, @travel, @sources = self, nodes, point, travel, sources
      @whence = @sources.map(&:whence).inject(&:|)
    end
    
    def viable?
      @sources.all?(&:active?)
    end
    
    def replace!(&block)
      @neighbours = [ @sources[0].prev, @sources[1].next ]
      @neighbours.inject(&:==) ? block.call(prev) : insert! if @neighbours.any?
      @sources.each do |source|
        block.call source
        source.collapsed = self
      end
    end
  end
  
  class Split
    include InteriorNode
    
    def initialize(nodes, point, travel, source, node)
      @original, @nodes, @point, @travel, @source, @node = self, nodes, point, travel, source, node
      @whence = source.whence | node.whence
    end
    
    def viable?
      return false unless @source.active?
      @edge = @node.splits.map(&:current).compact.select do |node|
        node.headings[1].equal? @node.headings[1]
      end.map do |node|
        [ node, node.next ]
      end.find do |pair|
        e0, e1 = pair.map(&:point)
        h0, h1 = pair.map(&:heading)
        next if point.minus(e0).cross(h0) < 0
        next if point.minus(e1).cross(h1) > 0
        true
      end
    end
    
    def split!(index, &block)
      @neighbours = [ @source.neighbours[index], @edge[1-index] ].rotate index
      @neighbours.inject(&:equal?) ? block.call(prev, prev.is_a?(Collapse) ? 1 : 0) : insert! if @neighbours.any?
      @node.splits << self if index == 0
    end
    
    def replace!(&block)
      dup.split!(0, &block)
      dup.split!(1, &block)
      block.call @source
    end
  end
  
  class Vertex
    include Node
    attr_reader :splits
    
    def initialize(nodes, point, index, headings)
      @original, @neighbours, @nodes, @whence, @point, @headings, @travel, @splits = self, [ nil, nil ], nodes, Set[index], point, headings, 0, Set[self]
    end
    
    def reflex?
      headings.inject(&:cross) < 0
    end
    
    def split(pair, limit)
      e0, e1 = pair.map(&:point)
      return if e0 == @point || e1 == @point
      h0, h1 = pair.map(&:heading)
      direction = pair[0].headings[1]
      travel = direction.dot(@point.minus e0) / (1 - secant * heading.dot(direction))
      return if travel < 0 || travel.nan? || travel.infinite?
      return if limit && travel >= limit
      point = heading.times(secant * travel).plus(@point)
      return if point.minus(e0).dot(direction) < 0
      return if point.minus(e0).cross(h0) < 0
      return if point.minus(e1).cross(h1) > 0
      Split.new @nodes, point, travel, self, pair[0]
    end
  end
  
  class Nodes
    def initialize(data, closed, limit = nil, options = {})
      @candidates, @closed, @limit = AVLTree.new, closed, limit
      rounding_angle = options.fetch("rounding-angle", DEFAULT_ROUNDING_ANGLE) * Math::PI / 180
      cutoff = options["cutoff"] && options["cutoff"] * Math::PI / 180
      nodes = data.sanitise(closed).tap do |lines|
        @repeats = lines.flatten(1).group_by { |point| point }.reject { |point, points| points.one? }
      end.map.with_index do |points, index|
        headings = if closed
          points.ring.map(&:difference).map(&:normalised).map(&:perp).ring.rotate(-1)
        else
          points.segments.map(&:difference).map(&:normalised).map(&:perp).unshift(nil).push(nil).segments
        end
        points.zip(headings).map do |point, headings|
          angle = headings.all? && Math::atan2(headings.inject(&:cross), headings.inject(&:dot))
          angle = -Math::PI if angle == Math::PI
          next Vertex.new(self, point, index, headings) unless angle && angle < 0
          extras = (angle.abs / rounding_angle).floor
          extras = 1 if cutoff && angle < -cutoff
          extras.times.map do |n|
            angle * (n + 1) / (extras + 1)
          end.map do |angle|
            headings[0].rotate_by(angle)
          end.unshift(headings.first).push(headings.last).segments.map do |headings|
            Vertex.new self, point, index, headings
          end
        end.flatten
      end
      nodes.map(&closed ? :ring : :segments).each do |edges|
        edges.each do |edge|
          edge[1].neighbours[0], edge[0].neighbours[1] = edge
        end
      end
      @active = nodes.flatten.to_set
    end
    
    def include?(node)
      @active.include? node
    end
    
    def insert(node)
      @active << node
      [ node, *node.neighbours ].compact.map(&:collapses).flatten.each do |collapse|
        @candidates << collapse unless @limit && collapse.travel >= @limit
      end
    end
    
    def progress(options = {}, &block)
      @active.map(&:collapses).flatten.each do |collapse|
        @candidates << collapse unless @limit && collapse.travel >= @limit
      end
      if options.fetch("splits", true)
        repeated_terminals, repeated_nodes = @active.select do |node|
          @repeats.include? node.point
        end.partition(&:terminal?)
        repeated_terminals.group_by(&:point).each do |point, nodes|
          nodes.permutation(2).select do |node1, node2|
            node1.prev && node2.next
          end.select do |node1, node2|
            node1.heading.cross(node2.heading) > 0
          end.group_by(&:first).map(&:last).map do |pairs|
            pairs.min_by do |node1, node2|
              node1.heading.dot node2.heading
            end
          end.compact.each do |node1, node2|
            @candidates << Split.new(self, point, 0, node1, node2)
          end
        end
        repeated_nodes.group_by(&:point).select do |point, nodes|
          nodes.all?(&:reflex?)
        end.each do |point, nodes|
          nodes.inject([]) do |(*sets, set), node|
            case
            when !set then                   [ [ node ] ]
            when set.last.next == node  then [ *sets, [ *set, node ] ]
            when set.first == node.next then [ *sets, [ node, *set ] ]
            else                             [ *sets,  set, [ node ] ]
            end
          end.sort_by do |set|
            set.first.heading.angle
          end.ring.each do |set0, set1|
            @candidates << Split.new(self, point, 0, set0.first, set1.last)
          end
        end if @closed
        pairs = @active.select(&:next).map do |node|
          [ node, node.next ]
        end
        pairs = RTree.load(pairs) do |pair|
          pair.map(&:point).transpose.map(&:minmax)
        end
        @active.select do |node|
          node.terminal? || node.reflex?
        end.map do |node|
          candidate, closer, travel, searched = nil, nil, @limit, Set.new
          loop do
            bounds = node.heading.times(node.secant * travel).plus(node.point).zip(node.point).map do |centre, coord|
              [ coord, centre - travel, centre + travel ].minmax
            end if travel
            break candidate unless pairs.search(bounds, searched).any? do |pair|
              closer = node.split pair, travel
            end
            candidate, travel = closer, closer.travel
          end
        end.compact.tap do |splits|
          @candidates.merge splits
        end
      end
      while candidate = @candidates.pop
        next unless candidate.viable?
        candidate.replace! do |node, index = 0|
          @active.delete node
          yield [ node, candidate ].rotate(index).map(&:original) if block_given?
        end
      end
      Enumerator.new do |yielder|
        while @active.any?
          nodes = [ @active.first ]
          while node = nodes.last.next and node != nodes.first
            nodes.push node
          end
          while node = nodes.first.prev and node != nodes.last
            nodes.unshift node
          end
          nodes.each do |node|
            @active.delete node
          end.map do |node|
            node.point.plus node.heading.times((@limit - node.travel) * node.secant)
          end.tap do |points|
            yielder << points
          end
        end
      end.to_a.sanitise(@closed) unless block_given?
    end
  end
  
  def straight_skeleton
    result = [ ]
    Nodes.new(self, true).progress do |nodes|
      result << nodes.map(&:point)
    end
    result
  end
  
  def centrelines_centrepoints(get_lines, get_points, fraction = 0.5)
    points = map(&:centroid) if get_points && all?(&:convex?)
    return [ points ] if points && !get_lines
    neighbours = Hash.new { |neighbours, node| neighbours[node] = [] }
    incoming, tails = Hash.new(0), Hash.new
    Nodes.new(self, true).progress do |node0, node1|
      incoming[node1] += 1
      neighbours[node0] << node1
      neighbours[node1] << node0
    end
    travel = neighbours.keys.map(&:travel).max
    points ||= incoming.select do |node, count|
      Split === node || count > 2 && node.travel > fraction * travel
    end.keys.sort_by(&:travel).reverse.map(&:point)
    return [ points ] unless get_lines
    loop do
      break unless neighbours.reject do |node, (neighbour, *others)|
        others.any? || neighbours[neighbour].one?
      end.each do |node, (neighbour, *)|
        next if neighbours[neighbour].one?
        neighbours.delete node
        neighbours[neighbour].delete node
        nodes, length = tails.delete(node) || [ [ node ], 0 ]
        candidate = [ nodes << neighbour, length + [ node.point, neighbour.point ].distance ]
        tails[neighbour] = [ tails[neighbour], candidate ].compact.max_by(&:last)
      end.any?
    end
    lengths, lines = Hash.new(0), Hash.new
    areas = map(&:signed_area)
    candidates = tails.values
    while candidates.any?
      (*nodes, node), length = candidates.pop
      next if (neighbours[node] - nodes).each do |neighbour|
        candidates << [ [ *nodes, node, neighbour ], length + [ node.point, neighbour.point ].distance ]
      end.any?
      index = nodes.map(&:whence).inject(node.whence, &:|).find do |index|
        areas[index] > 0
      end
      (*tail_nodes, node), tail_length = tails[node] || [ [ node ], 0 ]
      lengths[index], lines[index] = length + tail_length, nodes + tail_nodes.reverse if length + tail_length > lengths[index]
    end
    lines = lines.values.map do |nodes|
      nodes.chunk do |node|
        node.travel > fraction * travel
      end.select(&:first).map(&:last).reject(&:one?).map do |nodes|
        nodes.map(&:point)
      end
    end.flatten(1).sanitise(false)
    get_points ? [ lines, points ] : [ lines ]
  end
  
  def inset(closed, margin, options = {})
    return self if margin.zero?
    Nodes.new(self, closed, margin, options).progress(options)
  end
  
  def outset(closed, margin, options = {})
    return self if margin.zero?
    map(&:reverse).inset(closed, margin, options).map(&:reverse)
  end
  
  def buffer(closed, margin, overshoot = margin)
    case
    when !closed
      (self + map(&:reverse)).inset(closed, margin + overshoot).outset(closed, overshoot, "splits" => false)
    when margin > 0
      outset(closed, margin + overshoot).inset(closed, overshoot, "splits" => false)
    else
      inset(closed, -(margin + overshoot)).outset(closed, -overshoot, "splits" => false)
    end
  end
  
  def close_gaps(max_gap, max_area = true)
    outset(true, 0.5 * max_gap).remove_holes(max_area).inset(true, 0.5 * max_gap)
  end
  
  def smooth_in(closed, margin, cutoff = nil)
    inset(closed, margin).outset(closed, margin, "splits" => false, "cutoff" => cutoff)
  end
  
  def smooth_out(closed, margin, cutoff = nil)
    outset(closed, margin).inset(closed, margin, "splits" => false, "cutoff" => cutoff)
  end
  
  def smooth(closed, margin, cutoff = nil)
    smooth_in(closed, margin, cutoff).smooth_out(closed, margin, cutoff)
  rescue ArgumentError
    self
  end
end

Array.send :include, StraightSkeleton
