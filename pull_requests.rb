#!/usr/bin/env ruby

require 'optparse'
require_relative 'octokit_utils'

options = {}
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: release_planning.rb [options]'

  opts.on('-a', '--all', 'ALL THE THINGSS') { options[:all] = true }
  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
end

parser.parse!

missing = []
missing << '-n' if options[:namespace].nil?
missing << '-t' if options[:oauth].nil?
if not missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

options[:repo] = '.*' if options[:repo].nil?

util = OctokitUtils.new(options[:oauth])
repos = util.list_repos(options[:namespace], options[:repo])

repo_data = []

repos.each do |repo|
  begin
    pulls = util.fetch_pull_requests("#{options[:namespace]}/#{repo}")

    repo_data << { 'repo' => "#{options[:namespace]}/#{repo}", 'pulls' => pulls }
  rescue
    puts "Unable to fetch pull requests for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end

if options[:all]
  repo_data.each do |entry|
    puts "=== #{entry['repo']} ==="
    entry['pulls'].each do |pull|
      puts "  #{pull[:html_url]}"
    end
  end
end
