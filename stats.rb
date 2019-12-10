#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'optparse'
require 'csv'
require_relative 'octokit_utils'

output = File.read('modules.json')
parsed = JSON.parse(output)

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: stats.rb [options]'

  opts.on('-s', '--sort', 'Sort output based on number of pull requests') { options[:sort] = true }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
  opts.on('-o', '--overview', 'Output overview, summary totals to csv') { options[:display_overview] = true }
  opts.on('-w', '--work', 'Output PRs that need work to HTML') { options[:work] = true }
end

parser.parse!

missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

util = OctokitUtils.new(options[:oauth])

array_last_comment_pulls = []
array_uncommented_pulls = []
array_mentioned_pulls = []
array_puppet_uncommented_pulls = []
array_needs_rebase_no_label_pulls = []
array_needs_prompt_pulls = []
array_no_activity_pulls = []
total_rebase_pulls = 0
total_bad_status_pulls = 0
total_squashed_pulls = 0
total_open_pulls = 0
total_unmerged_pulls = 0
total_merged_pulls = 0
total_mentioned_pulls = 0

puts 'repo, last comment, needs rebase, fails test, needs squash, no comments, total open, has mention, no activty 40 days'
parsed.each do |m|
  # Disbled because default value on filter causes github api issues
  # rubocop:disable Lint/UselessAssignment
  pr_information_cache = util.fetch_async("#{m['github_namespace']}/#{m['repo_name']}", search_with = { state: 'open', sort: 'updated' }, filter = %i[statuses pull_request_commits issue_comments pull_request])

  closed_pr_information_cache = util.fetch_async("#{m['github_namespace']}/#{m['repo_name']}", search_with = { state: 'closed', sort: 'updated' }, filter = [])
  # rubocop:enable Lint/UselessAssignment

  # these are arrays used in generating the report
  # no comment from contributer in 30 days
  last_comment_pulls = util.fetch_pull_requests_with_last_owner_comment(pr_information_cache)
  array_last_comment_pulls += util.pulls_older_than((DateTime.now - 30).to_time, pulls: last_comment_pulls)
  # no comment from contributer in 15 days
  array_needs_prompt_pulls += util.pulls_older_than((DateTime.now - 15).to_time, pulls: last_comment_pulls)
  # no comment from anyone
  uncommented_pulls = util.fetch_uncommented_pull_requests(pr_information_cache)
  array_uncommented_pulls += uncommented_pulls
  # no comment from a puppet employee
  puppet_uncommented_pulls = util.fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
  array_puppet_uncommented_pulls += puppet_uncommented_pulls
  # last comment mentions a puppet person
  mentioned_pulls = util.fetch_pull_requests_mention_member(pr_information_cache)
  array_mentioned_pulls += mentioned_pulls
  total_mentioned_pulls += mentioned_pulls.size
  # prs that need rebase, report does not show prs with label, the graph/overview counts all prs (no label and has label)
  rebase_pulls = util.fetch_pull_requests_which_need_rebase(pr_information_cache)
  total_rebase_pulls += rebase_pulls.size
  rebase_pulls.each do |rebase|
    array_needs_rebase_no_label_pulls.push(rebase) unless util.does_pr_have_label("#{m['github_namespace']}/#{m['repo_name']}", rebase.number, 'needs-rebase')
  end
  # prs that have had no activity in 40 days
  no_activity_pulls = util.fetch_pull_requests_with_no_activity_40_days(pr_information_cache)
  array_no_activity_pulls += no_activity_pulls

  # failing tests
  bad_status_pulls = util.fetch_pull_requests_with_bad_status(pr_information_cache)
  total_bad_status_pulls += bad_status_pulls.size
  # needs squash
  squashed_pulls = util.fetch_pull_requests_which_need_squashed(pr_information_cache)
  total_squashed_pulls += squashed_pulls.size
  # total open pulls
  total_repo_open_pulls = []
  pr_information_cache.each do |iter|
    total_repo_open_pulls.push iter[:pull]
  end
  total_open_pulls += total_repo_open_pulls.size
  # total unmerged
  total_repo_unmerged_pulls = util.fetch_unmerged_pull_requests(closed_pr_information_cache)
  total_unmerged_pulls += total_repo_unmerged_pulls.size
  # total merged
  total_repo_merged_pulls = util.fetch_merged_pull_requests(closed_pr_information_cache)
  total_merged_pulls += total_repo_merged_pulls.size

  puts "#{m['github_namespace']}/#{m['repo_name']}, #{last_comment_pulls.size}, #{rebase_pulls.size}, #{bad_status_pulls.size}, #{squashed_pulls.size}, #{uncommented_pulls.size}, #{total_repo_open_pulls.size}, #{total_mentioned_pulls}, #{no_activity_pulls.size}"
end

if options[:display_overview]
  CSV.open('overview.csv', 'w') do |csv|
    csv << ['needs closed', 'needs rebase', 'fails tests', 'needs squashed', 'total PRs', 'uncommented']
    csv << [array_last_comment_pulls.size, total_rebase_pulls, total_bad_status_pulls, total_squashed_pulls, total_open_pulls, array_uncommented_pulls.size]
  end
  CSV.open('totals.csv', 'w') do |csv|
    csv << ['total unmerged PRs', 'total merged PRs', 'total open PRs', 'total uncommented open PRs']
    csv << [total_unmerged_pulls, total_merged_pulls, total_open_pulls, array_uncommented_pulls.size]
  end
end

stats_data = {
  'PRs that have 0 comments:' => array_uncommented_pulls,
  'Last comment from puppet, no response for 15 days (needs ping):' => array_needs_prompt_pulls,
  'Last comment from puppet, no response for 30 days (needs closed):' => array_last_comment_pulls,
  'PRs that have yet to be commented on by a puppet member:' => array_puppet_uncommented_pulls,
  'PRPRs that community have asked for help (mentioned a puppet member):' => array_mentioned_pulls,
  'PRPRs that require rebase (needs comment and a label):' => array_needs_rebase_no_label_pulls,
  'PRPRs that require closing=> no activity for 40 days:' => array_no_activity_pulls
}

html = ERB.new(File.read('stats.html.erb')).result(binding)

if options[:work]
  File.open('report.html', 'w+') do |f|
    f.puts(html)
  end
end
