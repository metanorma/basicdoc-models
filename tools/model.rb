# frozen_string_literal: true

# Canonical model loader for all tooling (site, validators, lint).
#
# Source of truth is the lutaml-lml parser (Pipeline.call): classes with
# attributes (name, type, cardinality, definition, visibility) and enums.
# Two parser gaps in lutaml-lml 0.1.5 are covered by a minimal text shim
# over the same file, confined to this file and exercised by every CI gate:
#   - data_type / primitive definitions are not surfaced at all
#   - class stereotypes come back empty
#   - fixed-value attributes (e.g. +type: "footnote") lose their quotes,
#     making literal values indistinguishable from type names
# When the parser closes these gaps, delete the shim.

require "lutaml/lml"

module BasicdocModel
  ROOT = File.expand_path("..", __dir__)
  BUILTINS = %w[Integer Boolean Float Text].freeze

  module_function

  Attr = Struct.new(:name, :type, :multiplicity, :definition, :visibility, keyword_init: true)
  Type = Struct.new(:name, :kind, :stereotype, :file, :definition, :attributes, :values, keyword_init: true)

  def load
    @load ||= begin
      types = {}
      Dir[File.join(ROOT, "models", "**/*.lml")].sort.each do |f|
        body = File.read(f)
        shims = shims_for(body)
        doc = Lutaml::Lml::Pipeline.call(body)

        (doc.classes || []).each do |k|
          next if types.key?(k.name)

          types[k.name] = Type.new(
            name: k.name, kind: "class", stereotype: shims[:stereo][k.name],
            file: f, definition: squash(k.definition),
            attributes: k.attributes.to_a.map { |a| build_attr(a, shims[:literals]) },
            values: []
          )
        end
        (doc.enums || []).each do |e|
          next if types.key?(e.name)

          types[e.name] = Type.new(
            name: e.name, kind: "enum", stereotype: shims[:stereo][e.name],
            file: f, definition: squash(e.definition),
            attributes: [], values: enum_values(e)
          )
        end
        shims[:stereo].each_key do |name|
          next if types.key?(name)

          kind = (/^\s*primitive\s+#{name}\b/.match?(body) ? "primitive" : "data type")
          types[name] = Type.new(
            name: name, kind: kind, stereotype: shims[:stereo][name], file: f,
            definition: shim_definition(body),
            attributes: [], values: []
          )
        end
      end
      types
    end
  end

  # textual facts the parser does not expose: type names with stereotypes
  # (all kinds), and fixed-value attribute literals
  def shims_for(body)
    stereo = {}
    body.scan(/^\s*(?:class|enum|data_type|primitive)\s+(\w+)(?:\s*<<([^>]+)>>)?(?:\s*\{)?\s*$/).each do |name, s|
      stereo[name] = s&.strip
    end
    literals = {}
    body.scan(/^\s*[+#-](\w+)\s*:\s*("[^"]*")\s*$/).each { |n, lit| literals[n] = lit }
    stereo.transform_values! { |s| s && "<<#{s}>>" }
    { stereo: stereo, literals: literals }
  end

  def squash(text)
    text.to_s.gsub(/\s+/, " ").strip
  end

  # data_type/primitive definitions, line-oriented (no nested-brace regex:
  # CodeQL flags that as catastrophic backtracking)
  def shim_definition(body)
    lines = body.lines
    start = lines.index { |l| l =~ /^\s*definition \{/ }
    return "" if start.nil?

    out = lines[(start + 1)..].take_while { |l| l !~ /^\s*\}/ }
    squash(out.join)
  end

  VISIBILITY_GLYPH = { "public" => "+", "private" => "-", "protected" => "#" }.freeze

  def glyph(visibility)
    VISIBILITY_GLYPH[visibility.to_s] || ""
  end

  def build_attr(parser_attr, literals)
    if literals.key?(parser_attr.name)
      Attr.new(name: parser_attr.name, type: literals[parser_attr.name],
              multiplicity: "fixed", definition: squash(parser_attr.definition),
              visibility: glyph(parser_attr.visibility))
    else
      c = parser_attr.cardinality
      mult = c.nil? || (c.min.to_s == "1" && c.max.to_s == "1") ? "1" : "#{c.min}..#{c.max}"
      Attr.new(name: parser_attr.name, type: parser_attr.type.to_s,
              multiplicity: mult, definition: squash(parser_attr.definition),
              visibility: glyph(parser_attr.visibility))
    end
  end

  def enum_values(enum)
    raw = enum.values.to_a.empty? ? enum.attributes.to_a : enum.values.to_a
    raw.map do |v|
      { name: v.respond_to?(:name) ? v.name.to_s : v.to_s,
        definition: squash(v.respond_to?(:definition) ? v.definition : nil) }
    end.reject { |h| h[:name] == "definition" }
  end

  # parents of a type, from view inheritance associations:
  # owner_type inheritance -> owner is parent; member_type -> member is parent
  def parents_of
    @parents_of ||= Dir[File.join(ROOT, "views", "*.lml")].each_with_object(Hash.new { |h, k| h[k] = [] }) do |v, acc|
      body = File.read(v)
      body.scan(/association \{\s*(?:.*?)\s*owner (\w+)\s+member (\w+)\s+owner_type inheritance/m).each do |parent, child|
        acc[child] << parent unless acc[child].include?(parent)
      end
      body.scan(/association \{\s*(?:.*?)\s*owner (\w+)\s+member (\w+)\s+member_type inheritance/m).each do |child, parent|
        acc[child] << parent unless acc[child].include?(parent)
      end
    end
  end

  def attributes_of(type_name, seen = {})
    t = load[type_name]
    return [] if t.nil? || seen[type_name]

    seen[type_name] = true
    t.attributes.map(&:name) + parents_of[type_name].flat_map { |p| attributes_of(p, seen) }
  end

  # names defined in a given file, for the file-name/type lint rule
  def names_in(path)
    File.read(path).scan(/^\s*(?:class|enum|data_type|primitive)\s+(\w+)/).flatten
  end
end
