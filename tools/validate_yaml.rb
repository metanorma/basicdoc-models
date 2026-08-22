# frozen_string_literal: true

# Validates examples/*.yaml instances against the LML model, parsed with
# lutaml-lml itself (no regex model extraction).
#
# YAML convention: every construct node carries `class` (the LML class
# name), LML attribute names as keys (inherited attributes count),
# `attributes` for register entries ({key, value(s), scheme}), `id` as the
# well-known anchor key, and `{text: ...}` maps as plain text leaves.

require "yaml"
require "lutaml/lml"

ROOT = File.expand_path("..", __dir__)
MODELS_DIR = File.join(ROOT, "models")
VIEWS_DIR = File.join(ROOT, "views")

def load_model
  classes = {}
  enums = {}
  Dir[File.join(MODELS_DIR, "**/*.lml")].sort.each do |f|
    doc = Lutaml::Lml::Pipeline.call(File.read(f))
    (doc.classes || []).each do |k|
      classes[k.name] ||= k
    end
    (doc.enums || []).each { |e| enums[e.name] ||= e }
  end
  [classes, enums]
end

CLASSES, ENUMS = load_model

# parents of a type: owner-side (owner is parent) and member-side
# (member is parent) inheritance associations, declared in views
def parents_of
  @parents_of ||= Dir[File.join(VIEWS_DIR, "*.lml")].each_with_object(Hash.new { |h, k| h[k] = [] }) do |v, acc|
    body = File.read(v)
    body.scan(/association \{\s*(?:.*?)\s*owner (\w+)\s*member (\w+)\s*owner_type inheritance/m).each do |parent, child|
      acc[child] << parent unless acc[child].include?(parent)
    end
    body.scan(/association \{\s*(?:.*?)\s*owner (\w+)\s*member (\w+)\s*member_type inheritance/m).each do |child, parent|
      acc[child] << parent unless acc[child].include?(parent)
    end
  end
end

def attributes_of(type, seen = {})
  return [] if seen[type] || CLASSES[type].nil?
  seen[type] = true
  own = CLASSES[type].attributes.to_a.map(&:name)
  inherited = parents_of[type].flat_map { |par| attributes_of(par, seen) }
  own + inherited
end

RESERVED = %w[class attributes id text].freeze

@errors = []

def check_node(node, where)
  case node
  when Hash
    return if node.keys == ["text"]
    if node.key?("key") && (node.keys - %w[key value scheme]).empty?
      @errors << "#{where}: register entry without key" if node["key"].to_s.empty?
      return
    end

    klass = node["class"]
    if klass.nil?
      @errors << "#{where}: node without class"
    elsif !CLASSES.key?(klass)
      @errors << "#{where}: unknown class #{klass}"
      return
    end

    attr_names = attributes_of(klass).uniq
    node.each do |k, v|
      next unless k.is_a?(String)
      if RESERVED.include?(k)
        check_node(v, "#{where}.#{k}") if v.is_a?(Hash) || v.is_a?(Array)
      elsif attr_names.include?(k)
        check_node(v, "#{where}.#{k}") if v.is_a?(Hash) || v.is_a?(Array)
      else
        @errors << "#{where}: '#{k}' is not an attribute of #{klass} (has: #{(attr_names + RESERVED).uniq.join(', ')})"
      end
    end
  when Array
    node.each_with_index { |child, i| check_node(child, "#{where}[#{i}]") }
  end
end

Dir[File.join(ROOT, "examples", "*.yaml")].sort.each do |path|
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
