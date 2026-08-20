# frozen_string_literal: true

require "erb"
require "fileutils"
require "pathname"

module BasicdocSite
  ModelType = Struct.new(
    :name, :kind, :stereotype, :file, :definition,
    :attributes, :values, keyword_init: true
  )
  Attribute = Struct.new(
    :visibility, :name, :type, :multiplicity, :definition, keyword_init: true
  )
  Plate = Struct.new(
    :slug, :title, :view_file, :image, :includes, :associations, :domains,
    :github_view_url, :tier, keyword_init: true
  )

  module_function

  ROOT = Pathname(__dir__).parent
  SITE = ROOT.join("site")
  OUT  = ROOT.join("_site")
  REPO = "https://github.com/metanorma/basicdoc-models"

  TIER_ORDER = %w[document sections blocks inline change datatypes].freeze
  SEGMENT_TIER = {
    "document" => "document", "bibdata" => "document", "contribmetadata" => "document"
  }.freeze
  TIER_DIRS = {
    "document" => %w[document bibdata contribmetadata]
  }.freeze
  TIER_DESCRIPTIONS = {
    "document"   => "The document aggregate, bibliographic basis, contribution and integrity metadata",
    "sections"   => "Hierarchical containers of content",
    "blocks"     => "Paragraph-level groupings: paragraphs, lists, tables, figures, sourcecode, amend markup",
    "inline"     => "Sub-paragraph elements: text formatting, media, cross-references, empty markers",
    "change"     => "Document and content patches for collaborative change management",
    "datatypes"  => "Cross-cutting primitives"
  }.freeze

  def h(str)
    str.to_s
       .gsub("&", "&amp;")
       .gsub("<", "&lt;")
       .gsub(">", "&gt;")
       .gsub('"', "&quot;")
  end

  def kebab(name)
    name
      .gsub(/([a-z0-9])([A-Z])/, '\1-\2')
      .gsub(/[\s_]+/, "-")
      .downcase
  end

  # —— LML parsing (line-based; consistent 2-space indentation in this repo) ——

  def parse_model_file(path)
    rel = Pathname(path).relative_path_from(ROOT).to_s
    types = []
    current = nil
    mode = nil            # :type_def | :attr_def | :value_def
    buffer = []
    anchor_indent = nil
    pending_attr = nil
    pending_value = nil

    File.foreach(path).with_index do |line, _i|
      stripped = line.strip
      indent = line[/^\s*/].length

      if mode
        closing = (stripped == "}" && indent == anchor_indent)
        if closing
          text = buffer.join(" ").gsub(/\s+/, " ").strip
          case mode
          when :type_def  then current.definition = text
          when :attr_def  then pending_attr.definition = text
          when :value_def then pending_value[:definition] = text
          end
          mode = nil
          buffer = []
          next
        end
        buffer << stripped unless stripped.empty?
        next
      end

      if (m = stripped.match(/\A(class|enum|data_type|primitive)\s+([A-Za-z_][A-Za-z0-9_]*)(\s*(<<[^>]+>>))?\s*\{/))
        current = ModelType.new(
          name: m[2], kind: m[1].tr("_", " "), stereotype: m[3]&.strip,
          file: rel, definition: nil, attributes: [], values: []
        )
        types << current
        pending_attr = nil
        pending_value = nil
        next
      end
      next unless current

      if (m = stripped.match(/\A([+#-])([a-z_][A-Za-z0-9_]*)\s*:\s*("[^"]*")\s*\z/))
        current.attributes << Attribute.new(
          visibility: m[1], name: m[2], type: m[3], multiplicity: "fixed", definition: nil
        )
        next
      end

      if (m = stripped.match(/\A([+#-])([a-z_][A-Za-z0-9_]*)\s*:\s*(.+?)(?:\s*\[([^\]]*)\])?\s*\{/))
        pending_attr = Attribute.new(
          visibility: m[1], name: m[2], type: m[3].strip,
          multiplicity: m[4] || "1", definition: nil
        )
        pending_value = nil
        current.attributes << pending_attr
        next
      end

      if current.kind == "enum" && (m = stripped.match(/\A([a-z_][A-Za-z0-9_]*)\s*\{\z/))
        pending_value = { name: m[1], definition: nil }
        pending_attr = nil
        current.values << pending_value
        next
      end

      if stripped == "definition {"
        mode = if pending_value then :value_def
               elsif pending_attr then :attr_def
               else :type_def
               end
        anchor_indent = indent
        next
      end
    end
    types
  end

  def load_models
    cache = {}
    Dir[ROOT.join("models/**/*.lml")].sort.each do |path|
      cache[Pathname(path).expand_path.to_s] = parse_model_file(path)
    end
    cache
  end

  def resolve_include(base_file, target)
    (Pathname(base_file).parent / target).expand_path
  end

  def load_plates(model_cache)
    Dir[ROOT.join("views/*.lml")].sort.map do |path|
      body = File.read(path)
      name = File.basename(path, ".lml")
      title = body[/^\s*title\s+"([^"]+)"/, 1] || name
      includes = body.scan(/^\s*include\s+(\S+)/).flatten
      associations = body.scan(/^\s*association\s*\{/).size
      resolved = includes.map { |inc| resolve_include(path, inc) }
      domains = includes.filter_map { |inc| inc[%r{models/([^/]+)/}, 1] }.uniq.sort
      tiers = resolved.filter_map do |p|
        m = p.to_s.match(%r{/models/([^/]+)/})
        next unless m && p.exist?

        SEGMENT_TIER[m[1]] || m[1]
      end
      tier = tiers.tally.max_by { |_, c| c }&.first || "document"
      Plate.new(
        slug: kebab(name), title: title, view_file: File.basename(path),
        image: "#{name}.png", includes: includes, associations: associations,
        domains: domains,
        github_view_url: "#{REPO}/blob/main/views/#{File.basename(path)}",
        tier: tier
      )
    end
  end

  # type name -> [plate slugs whose include closure defines it]
  def type_index(plates, model_cache)
    idx = Hash.new { |h, k| h[k] = [] }
    plates.each do |plate|
      view_path = ROOT.join("views/#{plate.view_file}")
      plate.includes.each do |inc|
        target = resolve_include(view_path, inc)
        next unless target.exist?

        (model_cache[target.to_s] || []).each do |t|
          idx[t.name] << plate.slug unless idx[t.name].include?(plate.slug)
        end
      end
    end
    idx
  end

  class PageContext
    def initialize(depth:, **vars)
      @depth = depth
      vars.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def asset_path(rel)
      "../" * @depth + rel
    end

    def h(str)
      BasicdocSite.h(str)
    end

    def type_href(name, from_depth)
      slugs = @type_index[name]
      return nil if slugs.nil? || slugs.empty?

      "#{"../" * from_depth}models/#{slugs.first}.html##{name}"
    end
  end

  def render(template_name, vars, depth:)
    ctx = PageContext.new(depth: depth, **vars)
    b = ctx.instance_eval { binding }
    vars.each { |k, v| b.local_variable_set(k, v) }
    template = File.read(SITE.join("templates/#{template_name}"))
    ERB.new(template, trim_mode: "-").result(b)
  end

  def write_page(path, inner_html, title:, description:, index_page:, depth:, git_sha:, build_date:)
    layout_html = render("layout.html.erb",
                         { content: inner_html,
                           page_title: title,
                           page_description: description,
                           index_page: index_page,
                           git_sha: git_sha,
                           build_date: build_date,
                           type_index: {} },
                         depth: depth)
    File.write(path, layout_html)
  end

  def copy_assets!
    FileUtils.rm_rf(OUT)
    %w[models domains assets/css assets/js images].each { |d| FileUtils.mkdir_p(OUT.join(d)) }
    FileUtils.cp(SITE.join("assets/css/site.css"), OUT.join("assets/css/site.css"))
    FileUtils.cp(SITE.join("assets/js/site.js"), OUT.join("assets/js/site.js"))
    Dir[ROOT.join("images/*.png")].each do |png|
      FileUtils.cp(png, OUT.join("images", File.basename(png)))
    end
  end

  def build!
    git_sha = `git rev-parse --short HEAD`.strip
    build_date = Time.now.utc.strftime("%Y-%m-%d")
    model_cache = load_models
    plates = load_plates(model_cache)
    domains = plates.flat_map(&:domains).uniq.sort
    tindex = type_index(plates, model_cache)
    model_count = Dir[ROOT.join("models/**/*.lml")].size

    search_extra = Hash.new { |h, k| h[k] = [] }
    plates.each do |plate|
      view_path = ROOT.join("views/#{plate.view_file}")
      plate.includes.each do |inc|
        target = resolve_include(view_path, inc)
        next unless target.exist?

        (model_cache[target.to_s] || []).each do |ty|
          search_extra[plate.slug] << ty.name
          ty.attributes.each { |a| search_extra[plate.slug] << a.name }
        end
      end
    end

    copy_assets!

    index_html = render("index.html.erb",
                        { plates: plates, domains: domains, model_count: model_count,
                          tier_order: TIER_ORDER,
                          tier_descriptions: TIER_DESCRIPTIONS,
                          search_extra: search_extra,
                          git_sha: git_sha, build_date: build_date,
                          type_index: tindex },
                        depth: 0)
    write_page(OUT.join("index.html"), index_html,
               title: "Basicdoc Models — atlas",
               description: "Atlas of BasicDocument / SecureDoc LutaML model diagrams.",
               index_page: true, depth: 0,
               git_sha: git_sha, build_date: build_date)

    plates.each_with_index do |plate, i|
      view_path = ROOT.join("views/#{plate.view_file}")
      definitions = plate.includes.filter_map do |inc|
        target = resolve_include(view_path, inc)
        model_cache[target.to_s] if target.exist?
      end.flatten

      vars = {
        plate: plate,
        plate_index: i,
        plate_total: plates.size,
        prev_plate: i.positive? ? plates[i - 1] : nil,
        next_plate: plates[i + 1],
        definitions: definitions,
        git_sha: git_sha, build_date: build_date,
        type_index: tindex
      }
      model_html = render("model.html.erb", vars, depth: 1)
      write_page(OUT.join("models/#{plate.slug}.html"), model_html,
                 title: "#{plate.title} — Basicdoc Models",
                 description: "UML diagram plate and model definitions for #{plate.title} in the Basicdoc model atlas.",
                 index_page: false, depth: 1,
                 git_sha: git_sha, build_date: build_date)
    end

    TIER_ORDER.each do |tier|
      tier_plates = plates.select { |p| p.tier == tier }
      next if tier_plates.empty?

      dirs = TIER_DIRS[tier] || [tier]
      files = dirs.flat_map { |d| Dir[ROOT.join("models/#{d}/**/*.lml")] }.sort
      file_entries = files.map do |f|
        rel = Pathname(f).relative_path_from(ROOT).to_s
        { path: rel,
          github: "#{REPO}/blob/main/#{rel}",
          types: model_cache[Pathname(f).expand_path.to_s].map(&:name) }
      end
      domain_html = render("domain.html.erb",
                           { tier: tier,
                             tier_description: TIER_DESCRIPTIONS[tier] || "",
                             tier_plates: tier_plates,
                             file_entries: file_entries,
                             git_sha: git_sha, build_date: build_date,
                             type_index: tindex },
                           depth: 2)
      FileUtils.mkdir_p(OUT.join("domains/#{tier}"))
      write_page(OUT.join("domains/#{tier}/index.html"), domain_html,
                 title: "#{tier} domain — Basicdoc Models",
                 description: "Plates and LML files of the #{tier} domain in the Basicdoc model atlas.",
                 index_page: false, depth: 2,
                 git_sha: git_sha, build_date: build_date)
    end

    File.write(OUT.join(".nojekyll"), "")

    pages = 1 + plates.size + (TIER_ORDER & plates.map(&:tier)).size
    puts "site: wrote #{pages} pages -> #{OUT}"
  end
end
