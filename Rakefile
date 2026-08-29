PNG_MAGIC = "\x89PNG\r\n\x1a\n".b

VIEWS  = Rake::FileList["views/*.lml"]
IMAGES = VIEWS.pathmap("images/%n.png")

desc "Render diagrams from views (default)"
task render: IMAGES

rule(
  %r{^images/.+\.png$} => [
    proc do |tn|
      view = tn.sub(/^images\//, "views/").sub(/\.png$/, ".lml")
      includes = File.read(view).scan(/^\s*include\s+(\S+)/).flatten
        .map { |inc| File.expand_path(inc, File.dirname(view)) }
        .select { |p| File.exist?(p) }
      [view] + includes
    end
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

desc "Lint LML semantics: names, type resolution, view closure, visibility, definitions"
task :lint do
  sh "ruby", "-I", "tools", "-rbundler/setup", "tools/lint.rb"
end

desc "Validate examples/*.xml against grammars/basicdoc-compile.rnc (needs python3 + rnc2rng + lxml)"
task :"fixtures:xml" do
  sh "python3", "tools/validate_xml.py"
end

desc "Validate examples/*.yaml against the LML model"
task :"fixtures:yaml" do
  sh "ruby", "-I", "tools", "-rbundler/setup", "tools/validate_yaml.rb"
end

desc "Validate XML and YAML instance fixtures"
task fixtures: [:"fixtures:xml", :"fixtures:yaml"]

desc "Validate profile artifacts and their instances (narrowing-only rule enforced)"
task :profiles do
  sh "ruby", "-I", "tools", "-rbundler/setup", "tools/validate_profile.rb"
end

desc "Render, verify PNGs, lint, and check LML/RNC parity"
task check: %i[render verify lint parity]

desc "Build static model atlas into _site/ from views/*.lml metadata + images/"
task site: :render do
  require_relative "site/generate"
  BasicdocSite.build!
end

task default: :render
