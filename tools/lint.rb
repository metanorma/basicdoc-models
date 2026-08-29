# frozen_string_literal: true

# Semantic lint for the LML sources.
#
# Model facts (types, attributes, resolution) come from the canonical
# loader (tools/model.rb). Source-text rules (visibility markers,
# lowerCamelCase attribute names, definition blocks) are deliberately
# textual: they gate the source style, not the parsed result.

require_relative "model"

ERRORS = []
MODEL_FILES = Dir[File.join(BasicdocModel::ROOT, "models", "**/*.lml")]

# 1. file name must be a type defined in that file
# 2. no duplicate type definitions
defined = {}
MODEL_FILES.each do |f|
  types = BasicdocModel.names_in(f)
  stem = File.basename(f, ".lml")
  ERRORS << "#{f}: file name is not a type defined in this file (defines: #{types.join(', ')})" unless types.include?(stem)
  types.each { |t| (defined[t] ||= []) << f }
end
defined.each { |t, files| ERRORS << "duplicate type #{t}: #{files.join(', ')}" if files.size > 1 }

# 3. every attribute type resolves to a defined type or a builtin
BasicdocModel.load.each_value do |type|
  type.attributes.each do |a|
    next if a.multiplicity == "fixed" # literal value, not a type
    next if a.type.start_with?("<<") # stereotype-qualified reference

    tn = a.type.sub(/<<[^>]*>>\s*/, "").strip
    next if defined.key?(tn) || BasicdocModel::BUILTINS.include?(tn)

    ERRORS << "#{type.file}: attribute '#{a.name}' of #{type.name} references undefined type '#{tn}'"
  end
end

# 4-7. source-text rules
MODEL_FILES.each do |f|
  File.foreach(f).with_index do |line, i|
    m = line.match(/^\s*([+#-]?)([a-z_][A-Za-z0-9_]*)\s*:\s*([^\[{]+?)(?:\[[^\]]*\])?\s*\{?\s*$/)
    next unless m

    visibility, name, = m.captures
    ERRORS << "#{f}:#{i + 1}: attribute '#{name}' lacks a visibility marker (+/#/-)" if visibility.empty?
    ERRORS << "#{f}:#{i + 1}: attribute name '#{name}' should start lowercase" unless name[0] == name[0].downcase
  end
  body = File.read(f)
  ERRORS << "#{f}: class/enum without a definition block" if body =~ /^\s*(class|enum)\s/ && !body.include?("definition {")
end

# 8. view association owners/members resolve within the view's include closure
Dir[File.join(BasicdocModel::ROOT, "views", "*.lml")].each do |v|
  closure = {}
  File.read(v).scan(/^\s*include\s+(\S+)/).flatten.each do |inc|
    target = File.expand_path(inc, File.dirname(v))
    BasicdocModel.names_in(target).each { |t| closure[t] = true } if File.exist?(target)
  end
  File.foreach(v).with_index do |line, i|
    m = line.match(/^\s*(owner|member)\s+([A-Za-z_][A-Za-z0-9_]*)/)
    next unless m

    ERRORS << "#{v}:#{i + 1}: association #{m[1]} '#{m[2]}' not in include closure" unless closure[m[2]]
  end
end

if ERRORS.any?
  warn "lint: #{ERRORS.size} issue(s):\n  #{ERRORS.join("\n  ")}"
  exit 1
end
puts "lint: OK (#{MODEL_FILES.size} model files, #{defined.size} types)"
