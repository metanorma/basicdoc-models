# frozen_string_literal: true

# Validates examples/*.yaml instances against the LML model via the
# canonical loader (tools/model.rb): lutaml-lml parser + documented shims.
#
# YAML convention: every construct node carries `class` (the LML class
# name), LML attribute names as keys (inherited attributes count),
# `attributes` for register entries ({key, value(s), scheme}), `id` as the
# well-known anchor key, and `{text: ...}` maps or bare {key, value} maps
# (inline register entries) as leaves.

require "yaml"
require_relative "model"

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
    elsif !BasicdocModel.load.key?(klass)
      @errors << "#{where}: unknown class #{klass}"
      return
    end

    attr_names = BasicdocModel.attributes_of(klass).uniq
    node.each do |k, v|
      next unless k.is_a?(String)

      if RESERVED.include?(k) || attr_names.include?(k)
        check_node(v, "#{where}.#{k}") if v.is_a?(Hash) || v.is_a?(Array)
      else
        @errors << "#{where}: '#{k}' is not an attribute of #{klass} (has: #{(attr_names + RESERVED).uniq.join(', ')})"
      end
    end
  when Array
    node.each_with_index { |child, i| check_node(child, "#{where}[#{i}]") }
  end
end

Dir[File.join(BasicdocModel::ROOT, "examples", "*.yaml")].sort.each do |path|
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
