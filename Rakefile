PNG_MAGIC = "\x89PNG\r\n\x1a\n".b

VIEWS  = Rake::FileList["views/*.lml"]
IMAGES = VIEWS.pathmap("images/%n.png")

desc "Render diagrams from views (default)"
task render: IMAGES

rule(%r{^images/.+\.png$}) do |t|
  source = t.name.sub(/^images\//, "views/").sub(/\.png$/, ".lml")
  mkdir_p "images"
  sh "lutaml-lml", "generate", source, "-o", t.name, "-t", "png"
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

desc "Render, verify PNGs, and check LML/RNC parity"
task check: %i[render verify parity]

task default: :render
