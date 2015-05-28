#!/usr/bin/env ruby

require 'optparse'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: pull_requests.rb [options]'

  opts.on('-a', '--after DAYS', 'Pull requests that were last updated after DAYS days ago.') { |v| options[:after] = v.to_i }
  opts.on('-b', '--before DAYS', 'Pull requests that were last updated before DAYS days ago.') { |v| options[:before] = v.to_i }
  opts.on('-c', '--count', 'Only print the count of pull requests.') { options[:count] = true }
  opts.on('-e', '--show-empty', 'List repos with no pull requests') { options[:empty] = true }
  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-s', '--sort', 'Sort output based on number of pull requests') { options[:sort] = true }
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
if options[:before] and options[:after]
  puts "Only one of -a and -b can be specified"
  exit
end

options[:repo_regex] = '.*' if options[:repo_regex].nil?

util = OctokitUtils.new(options[:oauth])
repos = util.list_repos(options[:namespace], options)

repo_data = []

repos.each do |repo|
  begin
    pulls = util.fetch_pull_requests("#{options[:namespace]}/#{repo}")

    if options[:before]
      opts = { :pulls => pulls }
      start_time = (DateTime.now - options[:before]).to_time
      pulls = util.pulls_older_than(start_time, opts)
    elsif options[:after]
      opts = { :pulls => pulls }
      end_time = (DateTime.now - options[:after]).to_time
      pulls = util.pulls_newer_than(end_time, opts)
    end

    if not options[:empty] and pulls.empty?
      next
    end

    if options[:count]
      repo_data << { 'repo' => "#{options[:namespace]}/#{repo}", 'pulls' => nil, 'pull_count' => pulls.length }
    else
      repo_data << { 'repo' => "#{options[:namespace]}/#{repo}", 'pulls' => pulls, 'pull_count' => pulls.length }
    end
  rescue
    puts "Unable to fetch pull requests for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end

if options[:sort]
  repo_data.sort_by! { |x| -x['pull_count'] }
end

repo_data.each do |entry|
  puts "=== #{entry['repo']} ==="
  puts "  #{entry['pull_count']} open pull requests"
  unless options[:count]
    entry['pulls'].each do |pull|
      puts "  #{pull[:html_url]}"
    end
  end
end
