# frozen_string_literal: true

require "erb"
require "fileutils"
require "pathname"

module BasicdocSite
  Plate = Struct.new(
    :slug, :title, :view_file, :image, :includes, :associations, :domains,
    :github_view_url, keyword_init: true
  )

  module_function

  ROOT = Pathname(__dir__).parent
  SITE = ROOT.join("site")
  OUT  = ROOT.join("_site")
  REPO = "https://github.com/metanorma/basicdoc-models"

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

  def load_plates
    Dir[ROOT.join("views/*.lml")].sort.map do |path|
      body = File.read(path)
      name = File.basename(path, ".lml")
      title = body[/^\s*title\s+"([^"]+)"/, 1] || name
      includes = body.scan(/^\s*include\s+(\S+)/).flatten
      associations = body.scan(/^\s*association\s*\{/).size
      domains = includes.filter_map { |inc| inc[%r{models/([^/]+)/}, 1] }.uniq.sort
      Plate.new(
        slug: kebab(name),
        title: title,
        view_file: File.basename(path),
        image: "#{name}.png",
        includes: includes,
        associations: associations,
        domains: domains,
        github_view_url: "#{REPO}/blob/main/views/#{File.basename(path)}"
      )
    end
  end

  class PageContext
    def initialize(depth:, **vars)
      @depth = depth
      vars.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def asset_path(rel)
      @depth.zero? ? rel : "../#{rel}"
    end

    def h(str)
      BasicdocSite.h(str)
    end
  end

  def render(template_name, vars, depth:)
    ctx = PageContext.new(depth: depth)
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
                           build_date: build_date },
                         depth: depth)
    File.write(path, layout_html)
  end

  def build!
    git_sha = `git rev-parse --short HEAD`.strip
    build_date = Time.now.utc.strftime("%Y-%m-%d")
    plates = load_plates
    domains = plates.flat_map(&:domains).uniq.sort
    model_count = Dir[ROOT.join("models/**/*.lml")].size

    FileUtils.rm_rf(OUT)
    FileUtils.mkdir_p(OUT.join("models"))
    FileUtils.mkdir_p(OUT.join("assets/css"))
    FileUtils.mkdir_p(OUT.join("assets/js"))
    FileUtils.mkdir_p(OUT.join("images"))

    FileUtils.cp(SITE.join("assets/css/site.css"), OUT.join("assets/css/site.css"))
    FileUtils.cp(SITE.join("assets/js/site.js"), OUT.join("assets/js/site.js"))
    Dir[ROOT.join("images/*.png")].each do |png|
      FileUtils.cp(png, OUT.join("images", File.basename(png)))
    end

    index_html = render("index.html.erb",
                        { plates: plates, domains: domains, model_count: model_count,
                          git_sha: git_sha, build_date: build_date },
                        depth: 0)
    write_page(OUT.join("index.html"), index_html,
               title: "Basicdoc Models — atlas",
               description: "Atlas of BasicDocument / SecureDoc LutaML model diagrams.",
               index_page: true, depth: 0,
               git_sha: git_sha, build_date: build_date)

    plates.each_with_index do |plate, i|
      vars = {
        plate: plate,
        plate_index: i,
        plate_total: plates.size,
        prev_plate: i.positive? ? plates[i - 1] : nil,
        next_plate: plates[i + 1]
      }
      model_html = render("model.html.erb",
                          vars.merge(git_sha: git_sha, build_date: build_date), depth: 1)
      write_page(OUT.join("models/#{plate.slug}.html"), model_html,
                 title: "#{plate.title} — Basicdoc Models",
                 description: "UML diagram plate for #{plate.title} in the Basicdoc model atlas.",
                 index_page: false, depth: 1,
                 git_sha: git_sha, build_date: build_date)
    end

    File.write(OUT.join(".nojekyll"), "")

    puts "site: wrote #{plates.size + 1} pages -> #{OUT}"
  end
end
