#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'octokit_utils'

output = File.read('modules.json')
parsed = JSON.parse(output)

class PuppetModule
  attr_accessor :name, :namespace, :tag_date, :commits, :downloads
  def initialize(name, namespace, tag_date, commits, downloads = 0)
    @name = name
    @namespace = namespace
    @tag_date = tag_date
    @commits = commits
    @downloads = downloads
  end
end

puppet_modules = []
def number_of_downloads(module_name)
  uri = URI.parse("https://forgeapi.puppetlabs.com/v3/modules/#{module_name}")
  request =  Net::HTTP::Get.new(uri.path)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http| # pay attention to use_ssl if you need it
    http.request(request)
  end
  output = response.body
  parsed = JSON.parse(output)
  puts parsed

  begin
    parsed['current_release']['downloads']
  rescue NoMethodError
    "Error number of downloads #{module_name}"
  end
end

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: release_planning.rb [options]'

  opts.on('-c', '--commit-threshold NUM', 'Number of commits since release') { |v| options[:commits] = v.to_i }
  opts.on('-g', '--tag-regex REGEX', 'Tag regex') { |v| options[:tag_regex] = v }
  opts.on('-m', '--time-threshold DAYS', 'Days since release') { |v| options[:time] = v.to_i }

  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
  opts.on('-o', '--output', 'Creates html+json output') { options[:output] = true }
end

parser.parse!

missing = []
missing << '-t' if options[:oauth].nil?
missing << '-m or -c' if options[:time].nil? && options[:commits].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

options[:tag_regex] = '.*' if options[:tag_regex].nil?

util = OctokitUtils.new(options[:oauth])

repo_data = []

parsed.each do |m|
  begin
    latest_tag = util.fetch_tags("#{m['github_namespace']}/#{m['repo_name']}", options).first
    tag_ref = util.ref_from_tag(latest_tag)
    date_of_tag = util.date_of_ref("#{m['github_namespace']}/#{m['repo_name']}", tag_ref)
    commits_since_tag = util.commits_since_date("#{m['github_namespace']}/#{m['repo_name']}", date_of_tag)
    repo_data << { 'repo' => "#{m['github_namespace']}/#{m['repo_name']}", 'date' => date_of_tag, 'commits' => commits_since_tag, 'downloads' => number_of_downloads(m['forge_name']) }
    puppet_modules << PuppetModule.new(repo, "#{m['github_namespace']}/#{m['repo_name']}", date_of_tag, commits_since_tag)
  rescue StandardError
    puts "Unable to fetch tags for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end

puppet_modules.each { |puppet_module1| puts puppet_module1 }

due_by_commit = repo_data.select { |x| x['commits'] > options[:commits] } if options[:commits]

if options[:time]
  threshold = Time.now - options[:time]
  due_by_time = repo_data.select { |x| x['date'] < threshold }
end

due_for_release = if due_by_commit && due_by_time
                    due_by_commit & due_by_time
                  elsif due_by_commit
                    due_by_commit
                  else
                    due_by_time
                  end

due_for_release.each do |entry|
  puts "#{entry['repo']} is due for release. Last release was tagged on #{entry['date']} and there have been #{entry['commits']} commits since then."
end

html = []
html.push('<html>')
html.push("<head>")
html.push("<script src='./web_libraries/jquery.min.js' type='text/javascript'></script>")
html.push("<script src='./web_libraries/sorttable.js'></script><link rel='stylesheet' href='./web_libraries/bootstrap.min.css'>")
html.push("<script src='./web_libraries/DataTables/datatables.js'></script><link rel='stylesheet' href='./web_libraries/DataTables/datatables.css'>")

html.push("<script type= 'text/javascript'> $(document).ready( function () {$('#id_table').DataTable();} ); </script>")
html.push("</head>")


html.push('<body>')
html.push('<h2>Modules Requiring Release</h2>')
html.push("<table border='1' id = 'id_table' style='width:100%' class='sortable table table-hover'> <tr>")
html.push('<th>Module Name</th>')
html.push('<th>Last Release Tag Date</th>')
html.push('<th>Commits Since Then</th>')
html.push('<th>Number of downloads</th>')
html.push('</tr>')
repo_data.each do |puppet_module|
  html.push('<tr>')
  html.push("<td><a href='https://github.com/#{puppet_module['repo']}'>#{puppet_module['repo']}</a></td>")
  html.push("<td>#{puppet_module['date']}</td>")
  html.push("<td align=\"center\">#{puppet_module['commits']}</td>")
  html.push("<td align=\"center\">#{puppet_module['downloads']}</td>")
  html.push('</tr>')
end
html.push('</body>')
html.push('</html>')

if options[:output]
  File.open('ModulesRelease.html', 'w+') do |f|
    f.puts(html)
  end

  File.open('ModulesRelease.json', 'w') do |f|
    JSON.dump(due_for_release, f)
  end
end
