# frozen_string_literal: true

module PagesWorkflowContract
  WORKFLOW_RELATIVE = ".github/workflows/pages.yml"
  PINNED_ACTIONS = [
    "actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
    "actions/configure-pages@983d7736d9b0ae728b81ab479565c72886d7745b",
    "actions/upload-pages-artifact@56afc609e74202658d3ffba0e8f6dda462b719fa",
    "actions/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e"
  ].freeze

  def self.errors(root, source_dir:, required: false)
    expected = File.expand_path(WORKFLOW_RELATIVE, root)
    workflows = Dir.glob(File.join(root, ".github", "workflows", "*.{yml,yaml}"))
                   .select { |path| File.file?(path) }
                   .map { |path| File.expand_path(path) }
                   .sort

    return(required ? ["missing isolated Pages workflow: #{WORKFLOW_RELATIVE}"] : []) if workflows.empty?

    problems = []
    unexpected = workflows - [expected]
    problems << "only #{WORKFLOW_RELATIVE} is allowed; found #{unexpected.join(', ')}" unless unexpected.empty?
    return problems unless workflows.include?(expected)

    source = File.read(expected, encoding: "UTF-8")
    uses = source.scan(/^\s*uses:\s*(\S+)/).flatten
    problems << "Pages actions must match the pinned allowlist" unless uses == PINNED_ACTIONS
    {
      "push trigger on main" => ["push:", "branches: [main]"],
      "manual recovery trigger" => ["workflow_dispatch:"],
      "read-only source permission" => ["contents: read"],
      "Pages permission" => ["pages: write", "id-token: write"],
      "generated-site check" => ["run: ruby scripts/marketing_site.rb --check"],
      "isolated artifact staging" => ["rsync -a --delete --exclude DIRECTION.md #{source_dir}/ _site/"],
      "direction exclusion assertion" => ["test ! -e _site/DIRECTION.md"],
      "isolated upload path" => ["path: _site"]
    }.each do |label, fragments|
      problems << "Pages workflow missing #{label}" unless fragments.all? { |fragment| source.include?(fragment) }
    end
    problems << "Pages workflow must not consume repository secrets" if source.include?("secrets.")
    problems << "Pages workflow must not grant contents write" if source.match?(/^\s*contents:\s*write\s*$/)
    problems << "Pages workflow contains an unapproved trigger" if source.match?(/^\s{2}(?:pull_request|schedule|workflow_run|repository_dispatch):/)
    problems
  end
end
