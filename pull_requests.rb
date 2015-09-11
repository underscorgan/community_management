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

  # default filters
  opts.on('--puppetlabs', 'Select Puppet Labs\' modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = '^puppetlabs-'
  }

  opts.on('--puppetlabs-supported', 'Select only Puppet Labs\' supported modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = '^puppetlabs-(acl|apache|apt|aws|catalog_preview|concat|docker_platform|f5|firewall|haproxy|inifile|java|java_ks|mysql|netscaler|ntp|postgresql|powershell|reboot|registry|sqlserver|stdlib|tomcat|vcsrepo)'
  }

  opts.on('--community', 'Select community modules') {
    options[:namespace] = 'puppet-community'
    options[:repo_regex] = '^puppet-'
  }

  opts.on('--no-response', 'Select PRs which had no response in the last 30 days') {
    options[:before] = 30
  }

  opts.on('--needs-closing', 'Select PRs where the last response is from an owner, but no further activity for the last 30 days') {
    options[:before] = 30
    options[:last_comment] = :owner
  }

  opts.on('--bad-status', 'Select PRs where the status is bad') {
    options[:bad_status] = 1
  }

  opts.on('--needs-squashed', 'Select PRs that need squashed') {
    options[:needs_squashed] = 1
  }
  
  opts.on('--needs-rebase', 'Select PRs where they need a rebase') {
    options[:needs_rebase] = 1
  }

  opts.on('--no-comments', 'Select PRs where there are no comments') {
    options[:no_comments] = 1
  }

  opts.on('--no-puppet-comments', 'Select PRs where there are no comments from puppet members') {
    options[:no_puppet_comments] = 1
  }
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
    if options[:last_comment] == :owner
      pulls = util.fetch_pull_requests_with_last_owner_comment("#{options[:namespace]}/#{repo}")
    elsif options[:needs_rebase]
      pulls = util.fetch_pull_requests_which_need_rebase("#{options[:namespace]}/#{repo}")
    elsif options[:bad_status]
      pulls = util.fetch_pull_requests_with_bad_status("#{options[:namespace]}/#{repo}")
    elsif options[:needs_squashed]
      pulls = util.fetch_pull_requests_which_need_squashed("#{options[:namespace]}/#{repo}")
    elsif options[:no_comments]
      pulls = util.fetch_uncommented_pull_requests("#{options[:namespace]}/#{repo}")
    elsif options[:no_puppet_comments]
      pulls = util.fetch_pull_requests_with_no_puppet_personnel_comments("#{options[:namespace]}/#{repo}")
    else
      pulls = util.fetch_pull_requests("#{options[:namespace]}/#{repo}")
    end

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
  case entry['pull_count']
  when 0
    puts '  no open pull requests'
  when 1
    puts '  1 open pull request'
  else
    puts "  #{entry['pull_count']} open pull requests"
  end
  unless options[:count]
    entry['pulls'].each do |pull|
      puts "  #{pull[:html_url]} - #{pull[:title]}"
    end
  end
end
