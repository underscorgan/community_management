#!/usr/bin/env ruby

require 'optparse'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: release_planning.rb [options]'

  opts.on('-c', '--commit-threshold NUM', 'Number of commits since release') { |v| options[:commits] = v.to_i }
  opts.on('-g', '--tag-regex REGEX', 'Tag regex') { |v| options[:tag_regex] = v }
  opts.on('-m', '--time-threshold DAYS', 'Days since release') { |v| options[:time] = v.to_i }
  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
  opts.on('-o', '--output', 'Creates html output') { options[:output] = true }
end

parser.parse!

missing = []
missing << '-n' if options[:namespace].nil?
missing << '-t' if options[:oauth].nil?
missing << '-m or -c' if options[:time].nil? and options[:commits].nil?
if not missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

options[:repo_regex] = '.*' if options[:repo_regex].nil?
options[:tag_regex] = '.*' if options[:tag_regex].nil?

util = OctokitUtils.new(options[:oauth])
repos = util.list_repos(options[:namespace], options)

repo_data = []

repos.each do |repo|
  begin
    latest_tag = util.fetch_tags("#{options[:namespace]}/#{repo}", options).first
    tag_ref = util.ref_from_tag(latest_tag)
    date_of_tag = util.date_of_ref("#{options[:namespace]}/#{repo}", tag_ref)
    commits_since_tag = util.commits_since_date("#{options[:namespace]}/#{repo}", date_of_tag)

    repo_data << { 'repo' => "#{options[:namespace]}/#{repo}", 'date' => date_of_tag, 'commits' => commits_since_tag }
  rescue
    puts "Unable to fetch tags for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end

if options[:commits]
  due_by_commit = repo_data.select { |x| x['commits'] > options[:commits] }
end

if options[:time]
  threshold = Time.now - options[:time]
  due_by_time = repo_data.select { |x| x['date'] < threshold }
end

if due_by_commit and due_by_time
  due_for_release = due_by_commit & due_by_time
elsif due_by_commit
  due_for_release = due_by_commit
else
  due_for_release = due_by_time
end

due_for_release.each do |entry|
  puts "#{entry['repo']} is due for release. Last release was tagged on #{entry['date']} and there have been #{entry['commits']} commits since then."
end

html = []
html.push("<html>")
html.push("<head><link rel='stylesheet' href='https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/css/bootstrap.min.css'></head>")
html.push("<body>")
html.push("<h2>Modules Requiring Release</h2>")
html.push("<table cellpadding=\"20\">")
html.push("<tr>")
html.push("<th>Module Name</th>")
html.push("<th>Last Release Tag Date</th>")
html.push("<th>Commits Since Then</th>")
html.push("</tr>")
due_for_release.each do |entry|
  html.push("<tr>")
  html.push("<td>#{entry['repo']}</td>")
  html.push("<td>#{entry['date']}</td>")
  html.push("<td align=\"center\">#{entry['commits']}</td>")
  html.push("</tr>")
end
html.push("</body>")
html.push("</html>")

if options[:output]
  File.open("ModulesRelease.html", "w+") do |f|
    f.puts(html)
  end
end  
