#!/usr/bin/env ruby

require 'optparse'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: stats.rb [options]'

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
    options[:repo_regex] = '^puppetlabs-(acl|apache|apt|aws|catalog_preview|concat|docker_platform|f5|firewall|haproxy|inifile|java|java_ks|mysql|netscaler|ntp|postgresql|powershell|reboot|registry|sqlserver|stdlib|tomcat|vcsrepo)$'
  }

  opts.on('--community', 'Select community modules') {
    options[:namespace] = 'puppet-community'
    options[:repo_regex] = '^puppet-'
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

options[:repo_regex] = '.*' if options[:repo_regex].nil?

util = OctokitUtils.new(options[:oauth])
repos = util.list_repos(options[:namespace], options)

repo_data = []

puts "Repository, needs closed, needs rebase, fails tests, needs squashed, total"
repos.each do |repo|
  begin
    last_comment_pulls = util.fetch_pull_requests_with_last_owner_comment("#{options[:namespace]}/#{repo}")
    rebase_pulls = util.fetch_pull_requests_which_need_rebase("#{options[:namespace]}/#{repo}")
    bad_status_pulls = util.fetch_pull_requests_with_bad_status("#{options[:namespace]}/#{repo}")
    squashed_pulls = util.fetch_pull_requests_which_need_squashed("#{options[:namespace]}/#{repo}")
    total_pulls = util.fetch_pull_requests("#{options[:namespace]}/#{repo}")
  puts "#{options[:namespace]}/#{repo}, #{last_comment_pulls.size}, #{rebase_pulls.size}, #{bad_status_pulls.size}, #{squashed_pulls.size}, #{total_pulls.size}"
  rescue
    puts "Unable to fetch pull requests for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end
