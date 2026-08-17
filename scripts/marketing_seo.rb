# frozen_string_literal: true

require "cgi"
require "date"
require "fileutils"
require "json"
require "pathname"
require "securerandom"

# Additive SEO layer for the app-local PortfolioMarketingSite generator.
#
# The migration installs this module immediately before the generator CLI is
# executed, after PortfolioMarketingSite::Renderer and ::Generator exist.
module PortfolioMarketingSeo
  VERSION = "1.0.0"
  DEVELOPER_NAME = "Benjamin Dupin"
  DEVELOPER_PROFILE_URL = "https://apps.apple.com/fr/developer/benjamin-dupin/id1871474236"
  PORTFOLIO_URL = "https://bnjdpn.github.io/"

  OG_LANGUAGE_DEFAULTS = {
    "ar" => "ar_SA", "ca" => "ca_ES", "cs" => "cs_CZ", "da" => "da_DK",
    "de" => "de_DE", "el" => "el_GR", "en" => "en_US", "es" => "es_ES",
    "fi" => "fi_FI", "fr" => "fr_FR", "he" => "he_IL", "hi" => "hi_IN",
    "hr" => "hr_HR", "hu" => "hu_HU", "id" => "id_ID", "it" => "it_IT",
    "ja" => "ja_JP", "ko" => "ko_KR", "ms" => "ms_MY", "nl" => "nl_NL",
    "no" => "no_NO", "pl" => "pl_PL", "pt" => "pt_BR", "ro" => "ro_RO",
    "ru" => "ru_RU", "sk" => "sk_SK", "sv" => "sv_SE", "th" => "th_TH",
    "tr" => "tr_TR", "uk" => "uk_UA", "vi" => "vi_VN",
    "zh-Hans" => "zh_CN", "zh-Hant" => "zh_TW"
  }.freeze

  SAFE_STAGE_EXTENSIONS = %w[
    .avif .css .html .ico .jpeg .jpg .js .png .svg .txt .webmanifest .webp .xml
  ].freeze

  class << self
    def install!
      return if @installed
      unless defined?(PortfolioMarketingSite::Renderer) && defined?(PortfolioMarketingSite::Generator)
        raise "PortfolioMarketingSite classes must be loaded before PortfolioMarketingSeo.install!"
      end

      PortfolioMarketingSite::Renderer.prepend(RendererPatch)
      PortfolioMarketingSite::Generator.prepend(GeneratorPatch)
      @installed = true
    end

    def og_locale(locale)
      normalized = locale.to_s.tr("_", "-")
      return "zh_CN" if normalized.downcase.start_with?("zh-hans")
      return "zh_TW" if normalized.downcase.start_with?("zh-hant")
      return normalized.tr("-", "_") if normalized.include?("-")

      OG_LANGUAGE_DEFAULTS.fetch(normalized, normalized)
    end

    def html_escape(value)
      CGI.escapeHTML(value.to_s)
    end

    def xml_escape(value)
      CGI.escapeHTML(value.to_s)
    end
  end

  module RendererPatch
    def render
      PortfolioMarketingSeo::SeoHtml.enrich(super, self)
    end

    # Search snippets may be tuned independently from the visible H1 and from
    # App Store Connect metadata. Missing entries intentionally fall through to
    # the app generator's existing localized title/description.
    def page_title
      config.fetch("seo_title_overrides", {}).fetch(locale, super)
    end

    def meta_description
      config.fetch("seo_description_overrides", {}).fetch(locale, super)
    end

    def language_options
      primary = config.fetch("primary_locale")
      super.map do |entry|
        copy = entry.dup
        copy[:url] = base_url if copy[:url] == "#{base_url}#{primary}/"
        copy
      end
    end

    def hreflang_links
      primary = config.fetch("primary_locale")
      links = super.map do |entry|
        copy = entry.dup
        copy[:url] = base_url if copy.fetch(:locale) == primary
        copy
      end

      config.fetch("hreflang_defaults", {}).each do |language, locale_code|
        links << { locale: language, url: seo_url_for_locale(locale_code) }
      end
      links.uniq { |entry| entry.fetch(:locale) }
    end

    def schema_data
      original = super.dup
      original.delete("@context")
      original.delete("author")

      developer_name = config.fetch("developer_name")
      developer_profile_url = config.fetch("developer_profile_url")
      portfolio_url = config.fetch("portfolio_url")
      person_id = "#{portfolio_url}#benjamin-dupin"
      software_id = "#{base_url}#software"
      website_id = "#{base_url}#website"
      webpage_id = "#{canonical_url}#webpage"

      person = {
        "@type" => "Person",
        "@id" => person_id,
        "name" => developer_name,
        "url" => portfolio_url,
        "sameAs" => [developer_profile_url]
      }

      software = original.merge(
        "@id" => software_id,
        "url" => base_url,
        "author" => { "@id" => person_id },
        "publisher" => { "@id" => person_id },
        "inLanguage" => html_lang
      )
      software["sameAs"] = [app_store_url] if app_store_url

      website = {
        "@type" => "WebSite",
        "@id" => website_id,
        "url" => base_url,
        "name" => app_name,
        "publisher" => { "@id" => person_id }
      }

      webpage = {
        "@type" => "WebPage",
        "@id" => webpage_id,
        "url" => canonical_url,
        "name" => page_title,
        "description" => meta_description,
        "inLanguage" => html_lang,
        "isPartOf" => { "@id" => website_id },
        "about" => { "@id" => software_id },
        "author" => { "@id" => person_id }
      }

      { "@context" => "https://schema.org", "@graph" => [person, website, software, webpage] }
    end

    private

    def seo_url_for_locale(locale_code)
      locale_code == config.fetch("primary_locale") ? base_url : "#{base_url}#{locale_code}/"
    end
  end

  module SeoHtml
    module_function

    def enrich(html, renderer)
      output = html.dup
      # Some generator families render their bespoke 404 through Renderer too.
      # Keep those noindex pages free of marketing metadata and footer links.
      if output.match?(/<meta\b[^>]*name=["']robots["'][^>]*content=["'][^"']*noindex/i)
        return optimize_images(output, renderer)
      end
      output.gsub!(/<meta\b[^>]*(?:property=["']og:[^"']+["']|name=["']twitter:[^"']+["']|name=["']author["'])[^>]*>\s*/i, "")
      output.gsub!(/<link\b[^>]*rel=["']author["'][^>]*>\s*/i, "")
      raise "Rendered page has no </head>" unless output.include?("</head>")

      config = renderer.config
      locale = renderer.locale
      image_url = config.fetch("base_url") + config.fetch("social_image_path")
      image_alt = localized_hero_alt(config.fetch("design_contract")["hero_alt"], locale)
      image_alt ||= [renderer.send(:marketing_name), renderer.send(:subtitle)].reject(&:empty?).join(" — ")
      image_alt = renderer.app_name if image_alt.empty?
      current_og_locale = PortfolioMarketingSeo.og_locale(locale)
      alternate_og_locales = config.fetch("locales").map do |entry|
        PortfolioMarketingSeo.og_locale(entry.fetch("code"))
      end.uniq.reject { |entry| entry == current_og_locale }

      tags = []
      tags << meta("name", "author", config.fetch("developer_name"))
      tags << %(<link rel="author" href="#{h(config.fetch("developer_profile_url"))}">)
      tags << meta("property", "og:type", "website")
      tags << meta("property", "og:site_name", renderer.app_name)
      tags << meta("property", "og:locale", current_og_locale)
      alternate_og_locales.each { |entry| tags << meta("property", "og:locale:alternate", entry) }
      tags << meta("property", "og:title", renderer.send(:page_title))
      tags << meta("property", "og:description", renderer.send(:meta_description))
      tags << meta("property", "og:url", renderer.send(:canonical_url))
      tags << meta("property", "og:image", image_url)
      tags << meta("property", "og:image:secure_url", image_url)
      tags << meta("property", "og:image:type", config.fetch("social_image_type"))
      tags << meta("property", "og:image:width", config.fetch("social_image_width"))
      tags << meta("property", "og:image:height", config.fetch("social_image_height"))
      tags << meta("property", "og:image:alt", image_alt)
      tags << meta("name", "twitter:card", "summary_large_image")
      tags << meta("name", "twitter:title", renderer.send(:page_title))
      tags << meta("name", "twitter:description", renderer.send(:meta_description))
      tags << meta("name", "twitter:image", image_url)
      tags << meta("name", "twitter:image:alt", image_alt)

      output = optimize_images(output, renderer)
      output = add_footer_links(output, renderer)
      output.sub!("</head>", "  #{tags.join("\n  ")}\n</head>")
      output
    end

    def localized_hero_alt(value, locale)
      return value unless value.is_a?(Hash)
      language = locale.to_s.tr("_", "-")
      language = if language.downcase.start_with?("zh-hans")
                   "zh-Hans"
                 elsif language.downcase.start_with?("zh-hant")
                   "zh-Hant"
                 else
                   language.split("-").first.downcase
                 end
      selected = value[locale] || value[language] || value["en"] || value["default"]
      selected.is_a?(String) && !selected.empty? ? selected : nil
    end

    def add_footer_links(html, renderer)
      return html if html.include?("data-portfolio-seo-links")
      raise "Rendered page has no footer" unless html.include?("</footer>")

      ui = renderer.send(:ui)
      label = ui.fetch("more_apps_short", "More apps")
      config = renderer.config
      block = %(<nav class="seo-author-links" data-portfolio-seo-links aria-label="#{h(label)}"><a href="#{h(config.fetch("portfolio_url"))}">#{h(label)}</a><a href="#{h(config.fetch("developer_profile_url"))}">#{h(config.fetch("developer_name"))} · App Store</a></nav>)
      if html.match?(/<small\b[^>]*class=["'][^"']*trademark-notice/i)
        html.sub(/(?=<small\b[^>]*class=["'][^"']*trademark-notice)/i, "#{block}\n")
      else
        html.sub("</footer>", "#{block}\n</footer>")
      end
    end

    def optimize_images(html, renderer)
      config = renderer.config
      base_url = config.fetch("base_url")
      screenshots = config.fetch("screenshots", {}).values.flatten
      related_paths = config.fetch("related_apps", []).map { |entry| entry["icon_path"] }.compact
      hero_path = config.fetch("design_contract").fetch("hero_raster")
      hero_width = config.fetch("design_contract").fetch("hero_width")
      hero_height = config.fetch("design_contract").fetch("hero_height")

      html.gsub(/<img\b[^>]*>/i) do |tag|
        source = tag[/\bsrc=["']([^"']+)["']/i, 1]
        next tag unless source
        source = CGI.unescapeHTML(source)

        screenshot = screenshots.find do |entry|
          url = entry.fetch("url")
          relative = url.start_with?(base_url) ? url.delete_prefix(base_url) : nil
          source == url || (relative && source.end_with?(relative))
        end
        if screenshot
          tag = upsert_attribute(tag, "width", screenshot.fetch("width"))
          tag = upsert_attribute(tag, "height", screenshot.fetch("height"))
          tag = upsert_attribute(tag, "decoding", "async")
        elsif related_paths.any? { |path| source.end_with?(path) }
          tag = upsert_attribute(tag, "loading", "lazy")
          tag = upsert_attribute(tag, "decoding", "async")
        elsif source.end_with?(hero_path)
          tag = upsert_attribute(tag, "width", hero_width)
          tag = upsert_attribute(tag, "height", hero_height)
          tag = upsert_attribute(tag, "decoding", "async")
        end
        tag
      end
    end

    def upsert_attribute(tag, name, value)
      escaped = h(value)
      pattern = /\s#{Regexp.escape(name)}=["'][^"']*["']/i
      return tag.sub(pattern, %( #{name}="#{escaped}")) if tag.match?(pattern)

      tag.sub(/\s*\/?>\z/) do |ending|
        closing = ending.include?("/") ? " />" : ">"
        %( #{name}="#{escaped}"#{closing})
      end
    end

    def meta(attribute, key, value)
      %(<meta #{attribute}="#{h(key)}" content="#{h(value)}">)
    end

    def h(value)
      PortfolioMarketingSeo.html_escape(value)
    end
  end

  module GeneratorPatch
    def stage!(target_name)
      target = Pathname.new(target_name.to_s)
      target = repo_root.join(target) unless target.absolute?
      target = target.expand_path
      expected = repo_root.join("_site").expand_path
      raise "--stage target must resolve exactly to #{expected}" unless target == expected
      raise "Refusing to replace existing stage directory #{target}" if target.exist?

      temporary = repo_root.join(".seo-stage-#{Process.pid}-#{SecureRandom.hex(6)}").expand_path
      raise "Unexpected stage temporary path" unless temporary.parent == repo_root && temporary.basename.to_s.start_with?(".seo-stage-")

      files = seo_stage_files
      begin
        temporary.mkpath
        files.each do |relative, content|
          validate_stage_relative!(relative)
          destination = temporary.join(relative).cleanpath
          unless destination.to_s.start_with?(temporary.to_s + File::SEPARATOR)
            raise "Stage path escapes target: #{relative}"
          end
          destination.dirname.mkpath
          File.open(destination, "wb") { |file| file.write(content.b) }
        end
        File.rename(temporary.to_s, target.to_s)
      rescue StandardError
        cleanup_stage_temporary(temporary)
        raise
      end

      puts "Staged exact Pages artifact for #{config.fetch("app_name")}: #{target} (#{files.length} files)."
      true
    end

    private

    def validate_config!
      super
      %w[
        developer_name developer_profile_url portfolio_url seo_last_modified hreflang_defaults
        web_icon_path web_icon_size web_icon_large_path web_icon_large_size
        social_image_path social_image_source social_image_type social_image_width social_image_height
      ].each do |key|
        raise "Missing #{key}" unless config.key?(key)
      end
      raise "developer_name must be #{DEVELOPER_NAME.inspect}" unless config.fetch("developer_name") == DEVELOPER_NAME
      raise "Unexpected developer profile URL" unless config.fetch("developer_profile_url") == DEVELOPER_PROFILE_URL
      raise "Unexpected portfolio URL" unless config.fetch("portfolio_url") == PORTFOLIO_URL
      Date.iso8601(config.fetch("seo_last_modified"))
      unless config.fetch("social_image_width").is_a?(Integer) && config.fetch("social_image_width").positive? &&
             config.fetch("social_image_height").is_a?(Integer) && config.fetch("social_image_height").positive?
        raise "SEO Open Graph dimensions must be positive integers"
      end
      unless config.fetch("web_icon_size") == 192 && config.fetch("web_icon_large_size") == 512
        raise "Web icon sizes must be exactly 192 and 512"
      end
      %w[web_icon_path web_icon_large_path social_image_source].each do |key|
        path = repo_root.join(config.fetch(key))
        raise "Missing SEO asset #{path}" unless path.file?
        raise "Refusing SEO asset symlink #{path}" if path.symlink?
      end
      social_mapping = config.fetch("local_assets", []).find do |asset|
        asset["source"] == config.fetch("social_image_source") && asset["path"] == config.fetch("social_image_path")
      end
      raise "social_image_source/path must have an exact local_assets mapping" unless social_mapping
      contract = config.fetch("design_contract")
      unless contract.fetch("hero_width").is_a?(Integer) && contract.fetch("hero_width").positive? &&
             contract.fetch("hero_height").is_a?(Integer) && contract.fetch("hero_height").positive?
        raise "Hero dimensions must be positive integers"
      end
      config.fetch("screenshots", {}).each_value do |entries|
        entries.each do |entry|
          unless entry.fetch("width").is_a?(Integer) && entry.fetch("width").positive? &&
                 entry.fetch("height").is_a?(Integer) && entry.fetch("height").positive?
            raise "Screenshot dimensions must be positive integers"
          end
        end
      end
      codes = config.fetch("locales").map { |entry| entry.fetch("code") }
      config.fetch("hreflang_defaults", {}).each do |language, target|
        raise "Invalid generic hreflang #{language.inspect}" if language.include?("-") || language.empty?
        raise "Unknown hreflang target #{target.inspect}" unless codes.include?(target)
      end
      {
        "seo_title_overrides" => 60,
        "seo_description_overrides" => 160
      }.each do |key, maximum|
        values = config.fetch(key, {})
        raise "#{key} must be an object" unless values.is_a?(Hash)
        values.each do |locale, value|
          raise "Unknown #{key} locale #{locale.inspect}" unless codes.include?(locale)
          unless value.is_a?(String) && !value.strip.empty?
            raise "#{key}[#{locale.inspect}] must be a non-empty string"
          end
          raise "#{key}[#{locale.inspect}] exceeds #{maximum} characters" if value.length > maximum
        end
      end
    end

    def source_digest(common_paths)
      extra = [
        repo_root.join("scripts/marketing_site.rb"), repo_root.join("scripts/marketing_seo.rb"),
        repo_root.join(config.fetch("web_icon_path")), repo_root.join(config.fetch("web_icon_large_path")),
        repo_root.join(config.fetch("social_image_source"))
      ]
      super(common_paths + extra)
    end

    def build_outputs
      outputs = super
      primary = config.fetch("primary_locale")
      outputs[managed(File.join(primary, "index.html"))] = seo_primary_redirect(primary)
      outputs[managed("assets/app-icon.png")] = repo_root.join(config.fetch("web_icon_path")).binread.force_encoding(Encoding::BINARY)
      outputs[managed("assets/app-icon-512.png")] = repo_root.join(config.fetch("web_icon_large_path")).binread.force_encoding(Encoding::BINARY)
      outputs[managed(config.fetch("social_image_path"))] = repo_root.join(config.fetch("social_image_source")).binread.force_encoding(Encoding::BINARY)
      outputs
    end

    def web_manifest
      manifest = super
      manifest["icons"] = [
        { "src" => "assets/app-icon.png", "sizes" => "192x192", "type" => "image/png" },
        { "src" => "assets/app-icon-512.png", "sizes" => "512x512", "type" => "image/png" }
      ]
      manifest
    end

    def sitemap
      links = seo_hreflang_links
      urls = [config.fetch("base_url")]
      config.fetch("locales").each do |entry|
        locale = entry.fetch("code")
        next if locale == config.fetch("primary_locale")
        urls << "#{config.fetch("base_url")}#{locale}/"
      end

      body = urls.map do |url|
        alternates = links.map do |entry|
          %(    <xhtml:link rel="alternate" hreflang="#{xml(entry.fetch(:locale))}" href="#{xml(entry.fetch(:url))}" />)
        end
        alternates << %(    <xhtml:link rel="alternate" hreflang="x-default" href="#{xml(config.fetch("base_url"))}" />)
        [
          "  <url>",
          "    <loc>#{xml(url)}</loc>",
          "    <lastmod>#{xml(config.fetch("seo_last_modified"))}</lastmod>",
          alternates,
          "  </url>"
        ].flatten.join("\n")
      end.join("\n")

      %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n#{body}\n</urlset>\n)
    end

    def seo_hreflang_links
      primary = config.fetch("primary_locale")
      links = config.fetch("locales").map do |entry|
        locale = entry.fetch("code")
        { locale: locale, url: locale == primary ? config.fetch("base_url") : "#{config.fetch("base_url")}#{locale}/" }
      end
      config.fetch("hreflang_defaults", {}).each do |language, target|
        links << { locale: language, url: target == primary ? config.fetch("base_url") : "#{config.fetch("base_url")}#{target}/" }
      end
      links.uniq { |entry| entry.fetch(:locale) }
    end

    def seo_primary_redirect(locale)
      base = CGI.escapeHTML(config.fetch("base_url"))
      name = CGI.escapeHTML(config.fetch("app_name"))
      lang = CGI.escapeHTML(locale)
      "<!doctype html>\n<html lang=\"#{lang}\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex,follow\"><meta http-equiv=\"refresh\" content=\"0; url=#{base}\"><link rel=\"canonical\" href=\"#{base}\"><title>#{name}</title></head><body><p><a href=\"#{base}\">Continue to #{name}</a></p></body></html>\n"
    end

    def seo_stage_files
      public_prefix = Pathname.new(config.fetch("docs_dir", "docs"))
      staged = {}
      build_outputs.each do |managed_path, content|
        path = Pathname.new(managed_path)
        relative = path.relative_path_from(public_prefix).cleanpath
        raise "Managed output escapes public root: #{managed_path}" if relative.to_s.start_with?("..")
        staged[relative.to_s] = seo_legal_path?(relative.to_s) ? seo_noindex(content) : content
      end

      seo_legal_candidates.each do |relative|
        next if staged.key?(relative)
        source = docs_root.join(relative)
        next unless source.file?
        raise "Refusing legal-page symlink #{source}" if source.symlink?
        staged[relative] = seo_noindex(source.binread)
      end
      staged
    end

    def seo_legal_candidates
      exact = %w[privacy.html terms.html privacy/index.html terms/index.html]
      one_level = %w[privacy.html terms.html].flat_map do |basename|
        Dir.glob(docs_root.join("*", basename).to_s).sort.map do |path|
          Pathname.new(path).relative_path_from(docs_root).to_s
        end
      end
      (exact + one_level).uniq.select do |relative|
        relative.match?(%r{\A(?:privacy|terms)\.html\z}) ||
          relative.match?(%r{\A[^/]+/(?:privacy|terms)\.html\z}) ||
          relative.match?(%r{\A(?:privacy|terms)/index\.html\z})
      end
    end

    def seo_legal_path?(relative)
      relative.match?(%r{\A(?:privacy|terms)\.html\z}) ||
        relative.match?(%r{\A[^/]+/(?:privacy|terms)\.html\z}) ||
        relative.match?(%r{\A(?:privacy|terms)/index\.html\z})
    end

    def seo_noindex(content)
      html = content.dup.force_encoding(Encoding::UTF_8)
      raise "Legal page is not UTF-8" unless html.valid_encoding?
      html.gsub!(/<link\b[^>]*rel=["'](?:canonical|alternate)["'][^>]*>\s*/i, "")
      html.gsub!(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>.*?<\/script>\s*/im, "")
      tag = %(<meta name="robots" content="noindex,follow">)
      if html.match?(/<meta\b[^>]*name=["']robots["'][^>]*>/i)
        html.sub!(/<meta\b[^>]*name=["']robots["'][^>]*>/i, tag)
      elsif html.match?(/<head(?:\s[^>]*)?>/i)
        html.sub!(/<head(?:\s[^>]*)?>/i) { |head| "#{head}\n  #{tag}" }
      else
        raise "Legal page has no head element"
      end
      html
    end

    def validate_stage_relative!(relative)
      path = Pathname.new(relative)
      raise "Stage path must be relative: #{relative}" if path.absolute? || path.cleanpath.to_s.start_with?("..")
      return if relative == ".nojekyll"
      extension = File.extname(relative).downcase
      raise "Disallowed staged file type #{relative}" unless SAFE_STAGE_EXTENSIONS.include?(extension)
      raise "Technical source leaked into stage: #{relative}" if relative.match?(/(?:\A|\/)(?:DIRECTION|README|AGENTS)\.md\z/i)
    end

    def cleanup_stage_temporary(path)
      return unless path.exist?
      unless path.parent == repo_root && path.basename.to_s.start_with?(".seo-stage-")
        raise "Refusing unsafe stage cleanup #{path}"
      end
      FileUtils.rm_rf(path.to_s)
    end

    def xml(value)
      PortfolioMarketingSeo.xml_escape(value)
    end
  end
end
