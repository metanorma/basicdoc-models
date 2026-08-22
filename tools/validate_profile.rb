# frozen_string_literal: true

# Validates profile artifacts (profiles/*.yaml) against the base model and,
# when a matching instance exists (examples/<profile>-document.yaml), checks
# the instance against the profile.
#
# Profiling rules (normative):
#   - exclude lists constructs that MUST NOT occur; every name must exist.
#   - constrain may only NARROW: new.min >= base.min AND new.max <= base.max.
#   - enums must be subsets of the base enumeration values.
#   - register.permit is the closed vocabulary of allowed register keys.
#
# Model extraction uses lutaml-lml (Pipeline.call), not regexes.

require "yaml"
require "lutaml/lml"

ROOT = File.expand_path("..", __dir__)

def load_model
  classes = {}
  enums = {}
  Dir[File.join(ROOT, "models", "**/*.lml")].sort.each do |f|
    doc = Lutaml::Lml::Pipeline.call(File.read(f))
    (doc.classes || []).each { |k| classes[k.name] ||= k }
    (doc.enums || []).each { |e| enums[e.name] ||= e }
  end
  [classes, enums]
end

CLASSES, ENUMS = load_model

def enum_values(name)
  e = ENUMS[name]
  return nil unless e
  (e.values.to_a.empty? ? e.attributes.to_a.map(&:name) : e.values.to_a).map(&:to_s) - ["definition"]
end

def parse_mult(str)
  return [nil, Float::INFINITY] if str == "*"
  if str =~ /\A(\d+)\.\.(\d+|\*)\z/
    [Regexp.last_match(1).to_i,
     Regexp.last_match(2) == "*" ? Float::INFINITY : Regexp.last_match(2).to_i]
  elsif str =~ /\A(\d+)\z/
    [Regexp.last_match(1).to_i, Regexp.last_match(1).to_i]
  end
end

def base_cardinality(type, attr)
  k = CLASSES[type]
  a = k&.attributes&.find { |x| x.name == attr }
  return nil unless a
  c = a.cardinality
  return nil unless c
  max = c.max == "*" ? Float::INFINITY : c.max.to_i
  [c.min.to_i, max]
end

@errors = []

def validate_profile(path)
  profile = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
  name = profile["profile"] || File.basename(path, ".yaml")
  @errors.clear

  (profile["exclude"] || []).each do |t|
    @errors << "#{name}: excluded construct #{t} does not exist" unless CLASSES.key?(t) || ENUMS.key?(t)
  end
  excluded = profile["exclude"] || []

  (profile["constrain"] || {}).each do |target, mult|
    type, attr = target.split(".")
    base = base_cardinality(type, attr)
    if base.nil?
      @errors << "#{name}: constrain target #{target} is not a model attribute"
      next
    end
    new = parse_mult(mult)
    if new.nil?
      @errors << "#{name}: constrain #{target} has unparseable multiplicity #{mult.inspect}"
      next
    end
    unless new[0] >= base[0] && new[1] <= base[1]
      @errors << "#{name}: constrain #{target} #{mult} WIDENS the base #{base[0]}..#{base[1] == Float::INFINITY ? "*" : base[1]} — profiles may only narrow"
    end
  end

  (profile["enums"] || {}).each do |enum_name, allowed|
    base_values = enum_values(enum_name)
    if base_values.nil?
      @errors << "#{name}: enum #{enum_name} does not exist"
      next
    end
    (allowed || []).each do |v|
      @errors << "#{name}: enum #{enum_name} value #{v} is not in the base" unless base_values.include?(v.to_s)
    end
  end

  permit = profile.dig("register", "permit") || []

  # instance check, if a matching twin exists
  slug = name.split("/").first
  instance = File.join(ROOT, "examples", "#{slug}-document.yaml")
  if File.exist?(instance)
    data = YAML.safe_load_file(instance, permitted_classes: [], aliases: false)
    data = data["document"] if data.is_a?(Hash) && data.key?("document")
    walk = lambda do |node, where|
      case node
      when Hash
        if (k = node["class"])
          @errors << "#{where}: construct #{k} is excluded by the profile" if excluded.include?(k)
          if k == "AdmonitionBlock" && permit # enum-constrained attr check for the worked example
            allowed = profile.dig("enums", "AdmonitionType")
            if allowed && !allowed.include?(node["type"].to_s) && node["type"]
              @errors << "#{where}: AdmonitionBlock.type #{node['type']} outside the profile enum subset"
            end
          end
        end
        (node["attributes"] || []).each do |entry|
          key = entry["key"] if entry.is_a?(Hash)
          if key && !permit.empty? && !permit.include?(key)
            @errors << "#{where}: register key '#{key}' not permitted by the profile"
          end
        end
        node.each_value { |v| walk.call(v, where) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array
        node.each_with_index { |c, i| walk.call(c, "#{where}[#{i}]") }
      end
    end
    walk.call(data, File.basename(instance))
  end

  [name, @errors]
end

failed = 0
Dir[File.join(ROOT, "profiles", "*.yaml")].sort.each do |path|
  name, errors = validate_profile(path)
  if errors.empty?
    puts "profile: OK #{name}"
  else
    failed += 1
    puts "profile: FAIL #{name}"
    errors.each { |e| puts "  #{e}" }
  end
end
abort "profiles: #{failed} invalid" if failed.positive?
