#!/usr/bin/env ruby

require 'optparse'
require 'csv'
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
  opts.on('-o', '--overview', 'Display overview, summary totals') { options[:display_overview] = true}
  opts.on('-d', '--detailed', 'Display detailed view, per repo') { options[:display_detailed] = true}

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

total_last_comment_pulls = 0
total_rebase_pulls = 0
total_bad_status_pulls = 0
total_squashed_pulls = 0
total_open_pulls = 0
total_unmerged_pulls = 0
total_merged_pulls = 0

repos.each do |repo|
  last_comment_pulls = util.fetch_pull_requests_with_last_owner_comment("#{options[:namespace]}/#{repo}")
  total_last_comment_pulls = total_last_comment_pulls + last_comment_pulls.size
  rebase_pulls = util.fetch_pull_requests_which_need_rebase("#{options[:namespace]}/#{repo}")
  total_rebase_pulls = total_rebase_pulls + rebase_pulls.size
  bad_status_pulls = util.fetch_pull_requests_with_bad_status("#{options[:namespace]}/#{repo}")
  total_bad_status_pulls = total_bad_status_pulls + bad_status_pulls.size
  squashed_pulls = util.fetch_pull_requests_which_need_squashed("#{options[:namespace]}/#{repo}")
  total_squashed_pulls = total_squashed_pulls + squashed_pulls.size

  #total open pulls
  total_repo_open_pulls = util.fetch_pull_requests("#{options[:namespace]}/#{repo}")
  total_open_pulls = total_open_pulls + total_repo_open_pulls.size
  total_repo_unmerged_pulls = util.fetch_unmerged_pull_requests("#{options[:namespace]}/#{repo}")
  total_unmerged_pulls = total_unmerged_pulls + total_repo_unmerged_pulls.size
  total_repo_merged_pulls = util.fetch_merged_pull_requests("#{options[:namespace]}/#{repo}")
  total_merged_pulls = total_merged_pulls + total_repo_merged_pulls.size

  puts "#{options[:namespace]}/#{repo}, #{last_comment_pulls.size}, #{rebase_pulls.size}, #{bad_status_pulls.size}, #{squashed_pulls.size}, #{total_repo_open_pulls.size}"
  repo_data.push(["#{options[:namespace]}/#{repo}", last_comment_pulls.size, rebase_pulls.size, bad_status_pulls.size, squashed_pulls.size, total_repo_open_pulls.size])
end

if :display_overview
  CSV.open("overview.csv", "w") do |csv|
    csv << ["needs closed", "needs rebase", "fails tests", "needs squashed", "total PRs"]
    csv << [total_last_comment_pulls, total_rebase_pulls, total_bad_status_pulls, total_squashed_pulls, total_open_pulls]
  end
  CSV.open("totals.csv", "w") do |csv|
    csv << ["total unmerged PRs", "total merged PR's", "total open PRs"]
    csv << [total_unmerged_pulls, total_merged_pulls, total_open_pulls]
  end
end
