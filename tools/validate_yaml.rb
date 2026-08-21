# frozen_string_literal: true

# Validates examples/*.yaml instances against the LML model.
#
# YAML convention: every construct node carries `class` (the LML class
# name); LML attribute names appear as keys (inherited attributes count);
# `attributes` holds register entries (bare {key, value(s), scheme} maps);
# `id` is the well-known register key for anchors; `{text: ...}` maps are
# plain text leaves.

require "yaml"

MODELS_DIR = File.expand_path("../models", __dir__)
VIEWS_DIR = File.expand_path("../views", __dir__)

def defined_types
  @defined_types ||= Dir[File.join(MODELS_DIR, "**/*.lml")].each_with_object({}) do |f, acc|
    File.read(f).scan(/^\s*(?:class|enum|data_type|primitive)\s+([A-Za-z_]\w*)/).flatten.each do |t|
      acc[t] ||= f
    end
  end
end

def body_of(type)
  File.read(defined_types[type]) if defined_types[type]
end

# parent = owner, child = member, for owner_type inheritance associations
def parent_of
  @parent_of ||= Dir[File.join(VIEWS_DIR, "*.lml")].each_with_object({}) do |v, acc|
    File.read(v).scan(/association \{\s*(?:.*?)\s*owner (\w+)\s*member (\w+)\s*owner_type inheritance/m).each do |parent, child|
        acc[child] ||= parent
      end
  end
end

def attributes_of(type)
  @attributes_of ||= {}
  @attributes_of[type] ||= begin
    own = body_of(type).to_s.scan(/^\s*[+#-]([a-z_]\w*)\s*:\s*([^\[{]+?)(?:\[[^\]]*\])?\s*\{/)
    inherited = parent_of[type] ? attributes_of(parent_of[type]) : []
    (own + inherited)
  end
end

def enum_values_of(type)
  body_of(type).to_s.scan(/^\s+([A-Za-z_]\w+) \{$/).flatten - %w[definition]
end

RESERVED = %w[class attributes id text].freeze

@errors = []

def check_node(node, where)
  case node
  when Hash
    if node.key?("key") && (node.keys - %w[key value scheme]).empty?
      @errors << "#{where}: register entry without key" if node["key"].to_s.empty?
      return
    end
    return if node.keys == ["text"]

    klass = node["class"]
    if klass.nil?
      @errors << "#{where}: node without class"
      return
    elsif !defined_types.key?(klass)
      @errors << "#{where}: unknown class #{klass}"
      return
    end

    attrs = attributes_of(klass)
    attr_names = attrs.map(&:first)
    enum_types = attrs.each_with_object({}) { |(n, t), h| h[n] = t.strip if enum_values_of(t.strip).any? }

    node.each do |k, v|
      if RESERVED.include?(k)
        check_node(v, "#{where}.#{k}") if v.is_a?(Hash) || v.is_a?(Array)
      elsif attr_names.include?(k)
        if enum_types[k] && v.is_a?(String) && !enum_values_of(enum_types[k]).include?(v)
          @errors << "#{where}: #{klass}.#{k} value '#{v}' not in enum #{enum_types[k]} (#{enum_values_of(enum_types[k]).join(', ')})"
        end
        check_node(v, "#{where}.#{k}") if v.is_a?(Hash) || v.is_a?(Array)
      else
        @errors << "#{where}: '#{k}' is not an attribute of #{klass} (has: #{(attr_names + RESERVED).uniq.join(', ')})"
      end
    end
  when Array
    node.each_with_index { |child, i| check_node(child, "#{where}[#{i}]") }
  end
end

Dir[File.expand_path("../examples/*.yaml", __dir__)].sort.each do |path|
  @errors.clear
  data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
  data = data["document"] if data.is_a?(Hash) && data.key?("document")
  check_node(data, File.basename(path))
  if @errors.empty?
    puts "fixtures:yaml OK #{File.basename(path)}"
  else
    puts "fixtures:yaml FAIL #{File.basename(path)}"
    @errors.each { |e| puts "  #{e}" }
    exit 1
  end
end
