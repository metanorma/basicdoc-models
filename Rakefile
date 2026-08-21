PNG_MAGIC = "\x89PNG\r\n\x1a\n".b

VIEWS  = Rake::FileList["views/*.lml"]
IMAGES = VIEWS.pathmap("images/%n.png")

desc "Render diagrams from views (default)"
task render: IMAGES

rule(
  %r{^images/.+\.png$} => [
    proc { |tn| tn.sub(/^images\//, "views/").sub(/\.png$/, ".lml") }
  ]
) do |t|
  mkdir_p "images"
  sh "lutaml-lml", "generate", t.source, "-o", t.name, "-t", "png"
end

desc "Remove rendered diagrams (only those regenerable from views)"
task :clean do
  rm_f IMAGES.existing
end

desc "Assert PNG magic bytes on every committed diagram"
task :verify do
  pngs = Rake::FileList["images/*.png"].existing.sort
  bad = pngs.reject { |p| File.binread(p, 8) == PNG_MAGIC }
  abort "verify: #{bad.size} of #{pngs.size} PNG(s) invalid:\n  #{bad.join("\n  ")}" unless bad.empty?
  puts "verify: #{pngs.size} PNG file(s) OK"
end

desc "Assert LML/RNC parity and hard views/models separation"
task :parity do
  errors = []

  errors << "missing grammars/basicdoc.rnc" unless File.exist?("grammars/basicdoc.rnc")
  errors << "missing grammars/basicdoc-compile.rnc" unless File.exist?("grammars/basicdoc-compile.rnc")
  errors << "missing models/" unless Dir.exist?("models")
  errors << "missing views/" unless Dir.exist?("views")

  included = []

  VIEWS.each do |v|
    body = File.read(v)
    errors << "no include in view: #{v}" unless body.match?(/^\s*include\s+/)
    body.each_line do |line|
      next unless line =~ /^\s*include\s+(\S+)/

      abs = File.expand_path(Regexp.last_match(1), File.dirname(v))
      included << abs if abs.end_with?(".lml") && abs.include?("/models/")
    end
  end

  # Every domain dir under models/ must be reachable from at least one view include.
  Dir["models/*"].select { |p| File.directory?(p) }.each do |dom_path|
    dom = File.basename(dom_path)
    domain_files = Dir["models/#{dom}/**/*.lml"].map { |p| File.expand_path(p) }
    next if domain_files.any? { |df| included.include?(df) }

    errors << "domain models/#{dom}/ not included by any view"
  end

  # Views vs models hard separation.
  Dir["models/**/*.lml"].each do |f|
    if File.read(f) =~ /^\s*(diagram|view)\b/
      errors << "#{f}: definition module contains diagram/view (belongs in views/)"
    end
  end
  Dir["views/*.lml"].each do |f|
    body = File.read(f)
    if body =~ /^\s*(class|enum|data_type)\s+/
      errors << "#{f}: view contains class/enum/data_type body (extract to models/ and include)"
    end
  end

  abort "parity: #{errors.size} issue(s):\n  #{errors.join("\n  ")}" unless errors.empty?
  puts "parity: OK (#{VIEWS.size} views, #{Dir['models/**/*.lml'].size} LML model files)"
end

BUILTIN_TYPES = %w[Integer Boolean Float Text].freeze

def lml_defined_types(path)
  File.read(path).scan(/^\s*(?:class|enum|data_type|primitive)\s+([A-Za-z_][A-Za-z0-9_]*)/).flatten
end

desc "Lint LML semantics: names, type resolution, view closure, visibility, definitions"
task :lint do
  errors = []
  model_files = Dir["models/**/*.lml"]

  # 1. file name must be a type defined in that file; 2. no duplicate definitions
  defined = {}
  model_files.each do |f|
    types = lml_defined_types(f)
    stem = File.basename(f, ".lml")
    errors << "#{f}: file name is not a type defined in this file (defines: #{types.join(', ')})" unless types.include?(stem)
    types.each do |t|
      (defined[t] ||= []) << f
    end
    # 5. class/enum bodies must carry a definition
    errors << "#{f}: class/enum without a definition block" if File.read(f) =~ /^\s*(class|enum)\s/ && !File.read(f).include?("definition {")
  end
  defined.each do |t, files|
    errors << "duplicate type #{t}: #{files.join(', ')}" if files.size > 1
  end

  # 3. every attribute type must resolve to a defined type or a built-in
  model_files.each do |f|
    File.foreach(f).with_index do |line, i|
      m = line.match(/^\s*([+#-]?)([a-z_][A-Za-z0-9_]*)\s*:\s*([^\[{]+?)(?:\[[^\]]*\])?\s*\{?\s*$/)
      next unless m

      visibility, name, raw_type = m.captures
      # 4. attributes need an explicit visibility marker
      errors << "#{f}:#{i + 1}: attribute '#{name}' lacks a visibility marker (+/#/-)" if visibility.empty?
      # 7. attribute names are lowerCamelCase (constructs are PascalCase types)
      errors << "#{f}:#{i + 1}: attribute name '#{name}' should start lowercase" unless name[0] == name[0].downcase
      type = raw_type.sub(/<<[^>]*>>\s*/, "").strip
      next if type.start_with?('"') # fixed-value attribute, e.g. +type: "callout"
      next if defined.key?(type) || BUILTIN_TYPES.include?(type)

      errors << "#{f}:#{i + 1}: attribute '#{name}' references undefined type '#{type}'"
    end
  end

  # 6. view association owners/members must resolve within the view's include closure
  Dir["views/*.lml"].each do |v|
    closure = {}
    File.read(v).scan(/^\s*include\s+(\S+)/).flatten.each do |inc|
      target = File.expand_path(inc, File.dirname(v))
      lml_defined_types(target).each { |t| closure[t] = true } if File.exist?(target)
    end
    File.foreach(v).with_index do |line, i|
      m = line.match(/^\s*(owner|member)\s+([A-Za-z_][A-Za-z0-9_]*)/)
      next unless m

      errors << "#{v}:#{i + 1}: association #{m[1]} '#{m[2]}' not in include closure" unless closure[m[2]]
    end
  end

  abort "lint: #{errors.size} issue(s):\n  #{errors.join("\n  ")}" unless errors.empty?
  puts "lint: OK (#{model_files.size} model files, #{defined.size} types)"
end

desc "Render, verify PNGs, lint, and check LML/RNC parity"
task check: %i[render verify lint parity]

desc "Build static model atlas into _site/ from views/*.lml metadata + images/"
task :site do
  require_relative "site/generate"
  BasicdocSite.build!
end

task default: :render
