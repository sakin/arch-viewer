# PROTOTYPE scanner. Throwaway. Reads a Rails app/ folder with Prism and
# writes the IR as JSON: classes, methods (with a rough complexity), constant
# references and association edges.
#
#   ruby scan.rb /path/to/rails_app > ir.json
require "prism"
require "json"

root = File.expand_path(ARGV.fetch(0))
files = Dir[File.join(root, "app/**/*.rb")].reject { |f| f.end_with?("preview.rb") }.sort

ASSOC = %w[belongs_to has_many has_one has_and_belongs_to_many delegated_type].freeze
BRANCHES = [Prism::IfNode, Prism::UnlessNode, Prism::WhenNode, Prism::AndNode, Prism::OrNode,
            Prism::RescueNode, Prism::WhileNode, Prism::UntilNode, Prism::RescueModifierNode].freeze

def const_name(node)
  case node
  when Prism::ConstantReadNode then node.name.to_s
  when Prism::ConstantPathNode then node.full_name rescue nil
  end
end

def count_branches(node)
  return 0 unless node
  n = BRANCHES.any? { |k| node.is_a?(k) } ? 1 : 0
  # Safe navigation (&.) is a branch too.
  n += 1 if node.is_a?(Prism::CallNode) && node.safe_navigation?
  node.compact_child_nodes.sum { |c| count_branches(c) } + n
end

def camelize(sym) = sym.to_s.split("_").map(&:capitalize).join

classes = []

files.each do |path|
  rel = path.delete_prefix(root + "/")
  src = File.read(path)
  result = Prism.parse(src)
  folder = rel.split("/")[1] # models, controllers, ...
  folder = "models/concerns" if rel.start_with?("app/models/concerns")
  folder = "controllers/concerns" if rel.start_with?("app/controllers/concerns")
  folder = "components" if rel.start_with?("app/views/components")

  top = nil
  nesting = []
  refs = Hash.new(0)
  assocs = []
  methods = []
  private_mode = false

  walk = lambda do |node, depth|
    return unless node
    case node
    when Prism::ClassNode, Prism::ModuleNode
      # The file's class is the first class, with its full namespace
      # (module ApplicationCable; class Connection -> ApplicationCable::Connection).
      # A file with no class gives its first module.
      full = (nesting + [const_name(node.constant_path)]).join("::")
      is_class = node.is_a?(Prism::ClassNode)
      if top.nil? || (is_class && top[:kind] == "module" && top[:wrapper])
        top = { name: full, kind: is_class ? "class" : "module",
                superclass: is_class ? const_name(node.superclass) : nil,
                line: node.location.start_line, wrapper: !is_class }
      end
      nesting.push(const_name(node.constant_path))
      node.compact_child_nodes.each { |c| walk.call(c, depth + 1) }
      nesting.pop
      return
    when Prism::ConstantReadNode, Prism::ConstantPathNode
      name = const_name(node)
      refs[name] += 1 if name
      return if node.is_a?(Prism::ConstantPathNode)
    when Prism::CallNode
      if node.receiver.nil? && node.name == :private && node.arguments.nil?
        private_mode = true
      end
      if node.receiver.nil? && ASSOC.include?(node.name.to_s) && node.arguments
        args = node.arguments.arguments
        sym = args.first
        if sym.is_a?(Prism::SymbolNode)
          opts = args.grep(Prism::KeywordHashNode).flat_map(&:elements)
          cn = opts.find { |e| e.key.is_a?(Prism::SymbolNode) && e.key.unescaped == "class_name" }
          poly = opts.any? { |e| e.key.is_a?(Prism::SymbolNode) && %w[polymorphic as].include?(e.key.unescaped) }
          through = opts.any? { |e| e.key.is_a?(Prism::SymbolNode) && e.key.unescaped == "through" }
          target = cn&.value.is_a?(Prism::StringNode) ? cn.value.unescaped : nil
          name = sym.unescaped
          target ||= node.name.to_s.start_with?("has_many", "has_and") ? camelize(name.sub(/s\z/, "").sub(/ie\z/, "y")) : camelize(name)
          assocs << { macro: node.name.to_s, name: name, target: target, polymorphic: poly, through: through,
                      line: node.location.start_line }
        end
      end
    when Prism::DefNode
      methods << {
        name: (node.receiver ? "self." : "") + node.name.to_s,
        line: node.location.start_line,
        end_line: node.location.end_line,
        visibility: private_mode ? "private" : "public",
        cc: 1 + count_branches(node.body)
      }
    end
    node.compact_child_nodes.each { |c| walk.call(c, depth + 1) }
  end
  walk.call(result.value, 0)
  next unless top

  # Scopes are methods too, for the card.
  src.each_line.with_index(1) do |line, i|
    if (m = line.match(/^\s*scope :(\w+)/))
      methods << { name: "scope #{m[1]}", line: i, end_line: i, visibility: "public", cc: 1 }
    end
  end
  methods.sort_by! { |m| m[:line] }

  top.delete(:wrapper)
  classes << top.merge(id: top[:name], folder: folder, file: rel, loc: src.lines.size,
                       methods: methods, refs: refs.reject { |k, _| k == top[:name] },
                       associations: assocs, source: src)
end

puts JSON.pretty_generate({ app: File.basename(root), scanned_at: Time.now.utc.iso8601, classes: classes })
