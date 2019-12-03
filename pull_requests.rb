#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'octokit_utils'
require 'json'

output = File.read('modules.json')
parsed = JSON.parse(output)

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: pull_requests.rb [options]'

  opts.on('-a', '--after DAYS', 'Pull requests that were last updated after DAYS days ago.') { |v| options[:after] = v.to_i }
  opts.on('-b', '--before DAYS', 'Pull requests that were last updated before DAYS days ago.') { |v| options[:before] = v.to_i }
  opts.on('-c', '--count', 'Only print the count of pull requests.') { options[:count] = true }
  opts.on('-e', '--show-empty', 'List repos with no pull requests') { options[:empty] = true }
  # opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  # opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-s', '--sort', 'Sort output based on number of pull requests') { options[:sort] = true }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }

  # default filters
  # opts.on('--puppetlabs', 'Select Puppet Labs\' modules') do
  #   options[:namespace] = 'puppetlabs'
  #   options[:repo_regex] = '^puppetlabs-'
  # end

  # opts.on('--puppetlabs-supported', 'Select only Puppet Labs\' supported modules') do
  #   options[:namespace] = 'puppetlabs'
  #   options[:repo_regex] = OctokitUtils::SUPPORTED_MODULES_REGEX
  # end

  # opts.on('--voxpupuli', 'Select Voxpupuli modules') do
  #   options[:namespace] = 'voxpupuli'
  #   options[:repo_regex] = '^puppet-'
  # end

  opts.on('--no-response', 'Select PRs which had no response in the last 30 days') do
    options[:before] = 30
  end

  opts.on('--needs-closing', 'Select PRs where the last response is from an owner, but no further activity for the last 30 days') do
    options[:before] = 30
    options[:last_comment] = :owner
  end

  opts.on('--bad-status', 'Select PRs where the status is bad') do
    options[:bad_status] = 1
  end

  opts.on('--needs-squashed', 'Select PRs that need squashed') do
    options[:needs_squashed] = 1
  end

  opts.on('--needs-rebase', 'Select PRs where they need a rebase') do
    options[:needs_rebase] = 1
  end

  opts.on('--no-comments', 'Select PRs where there are no comments') do
    options[:no_comments] = 1
  end

  opts.on('--no-puppet-comments', 'Select PRs where there are no comments from puppet members') do
    options[:no_puppet_comments] = 1
  end

  opts.on('--last-comment-mention-member', 'Select PRs where the last comment mentions a puppet members') do
    options[:comment_mention_member] = 1
  end

  opts.on('--no-activity-40-days', 'Select PRs where there has been no activity in 40 days') do
    options[:no_activity_40] = 1
  end
end

parser.parse!

missing = []
missing << '-n' if options[:namespace].nil?
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end
if options[:before] && options[:after]
  puts 'Only one of -a and -b can be specified'
  exit
end

options[:repo_regex] = '.*' if options[:repo_regex].nil?

util = OctokitUtils.new(options[:oauth])
#repos = util.list_repos(options[:namespace], options)

repo_data = []

 parsed.each do |repo|
  pr_information_cache = util.fetch_async("#{m['github_namespace']}/#{m['repo_name']}")
  begin
    pulls = if options[:last_comment] == :owner
              util.fetch_pull_requests_with_last_owner_comment(pr_information_cache)
            elsif options[:needs_rebase]
              util.fetch_pull_requests_which_need_rebase(pr_information_cache)
            elsif options[:bad_status]
              util.fetch_pull_requests_with_bad_status(pr_information_cache)
            elsif options[:needs_squashed]
              util.fetch_pull_requests_which_need_squashed(pr_information_cache)
            elsif options[:no_comments]
              util.fetch_uncommented_pull_requests(pr_information_cache)
            elsif options[:comment_mention_member]
              util.fetch_pull_requests_mention_member(pr_information_cache)
            elsif options[:no_puppet_comments]
              util.fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
            elsif options[:no_activity_40]
              util.fetch_pull_requests_with_no_activity_40_days(pr_information_cache)
            else
              util.fetch_pull_requests("#{m['github_namespace']}/#{m['repo_name']}")
            end

    if options[:before]
      opts = { pulls: pulls }
      start_time = (DateTime.now - options[:before]).to_time
      pulls = util.pulls_older_than(start_time, opts)
    elsif options[:after]
      opts = { pulls: pulls }
      end_time = (DateTime.now - options[:after]).to_time
      pulls = util.pulls_newer_than(end_time, opts)
    end

    next if !(options[:empty]) && pulls.empty?

    repo_data << if options[:count]
                   { 'repo' => "#{options[:namespace]}/#{repo}", 'pulls' => nil, 'pull_count' => pulls.length }
                 else
                   { 'repo' => "#{options[:namespace]}/#{repo}", 'pulls' => pulls, 'pull_count' => pulls.length }
                 end
  rescue StandardError
    puts "Unable to fetch pull requests for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end

repo_data.sort_by! { |x| -x['pull_count'] } if options[:sort]

repo_data.each do |entry|
  puts "=== #{entry['repo']} ==="
  case entry['pull_count']
  when 0
    puts '  no open pull requests'
  when 1
    puts '  1 open pull request'
  else
    puts "  #{entry['pull_count']} open pull requests"
  end
  next if options[:count]

  entry['pulls'].each do |pull|
    puts "  #{pull[:html_url]} - #{pull[:title]}"
  end
end
