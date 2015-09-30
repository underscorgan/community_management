#!/usr/bin/env ruby

require 'optparse'
require 'csv'
require_relative 'octokit_utils'

def tablecreation(title,pr_array)
  html = []
  html.push("<h2>#{title}</h2>")
  html.push("<table border='1' style='width:100%'> <tr>")
  html.push("<td>Title:</td><td>Author:</td><td>Location:</td></tr>")
  OctokitUtils.sort_pulls(pr_array).each do |pr|
    html.push("<tr><td> <a href='#{pr.html_url}'>#{pr.title}</a></td> <td>#{pr.user.login}</td>")
    if pr.head.repo != nil
      html.push("<td>#{pr.head.repo.name}</td>")
    end
    html.push("</tr>")
  end
  html.push("</table>")
  return html
end

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: stats.rb [options]'

  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-s', '--sort', 'Sort output based on number of pull requests') { options[:sort] = true }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
  opts.on('-o', '--overview', 'Output overview, summary totals to csv') { options[:display_overview] = true}
  opts.on('-w', '--work', 'Output PRs that need work to HTML') { options[:work] = true}

  # default filters
  opts.on('--puppetlabs', 'Select Puppet Labs\' modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = '^puppetlabs-'
  }

  opts.on('--puppetlabs-supported', 'Select only Puppet Labs\' supported modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = $supported_modules_regex
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

  puts "repo, last comment, needs rebase, fails test, needs squash, no comments, total open, has mention, no activty 40 days"
repos.each do |repo|
  #these are arrays used in generating the report
  #no comment from contributer in 30 days
  last_comment_pulls = util.fetch_pull_requests_with_last_owner_comment("#{options[:namespace]}/#{repo}")
  array_last_comment_pulls = array_last_comment_pulls + util.pulls_older_than((DateTime.now - 30).to_time, { :pulls => last_comment_pulls })
  #no comment from contributer in 15 days
  needs_prompt_pulls = util.fetch_pull_requests_with_last_owner_comment("#{options[:namespace]}/#{repo}")
  array_needs_prompt_pulls = array_needs_prompt_pulls + util.pulls_older_than((DateTime.now - 15).to_time, { :pulls => last_comment_pulls })
  #no comment from anyone
  uncommented_pulls = util.fetch_uncommented_pull_requests("#{options[:namespace]}/#{repo}")
  array_uncommented_pulls = array_uncommented_pulls + uncommented_pulls
  #no comment from a puppet employee
  puppet_uncommented_pulls = util.fetch_pull_requests_with_no_puppet_personnel_comments("#{options[:namespace]}/#{repo}")
  array_puppet_uncommented_pulls = array_puppet_uncommented_pulls + puppet_uncommented_pulls
  #last comment mentions a puppet person
  mentioned_pulls = util.fetch_pull_requests_mention_member("#{options[:namespace]}/#{repo}")
  array_mentioned_pulls = array_mentioned_pulls + mentioned_pulls
  total_mentioned_pulls = total_mentioned_pulls + mentioned_pulls.size
  #prs that need rebase, report does not show prs with label, the graph/overview counts all prs (no label and has label)
  rebase_pulls = util.fetch_pull_requests_which_need_rebase("#{options[:namespace]}/#{repo}")
  total_rebase_pulls = total_rebase_pulls + rebase_pulls.size
  rebase_pulls.each do |rebase|
    unless util.does_pr_have_label("#{options[:namespace]}/#{repo}", rebase.number, "needs-rebase")
      array_needs_rebase_no_label_pulls.push(rebase)
    end
  end
  #prs that have had no activity in 40 days
  no_activity_pulls = util.fetch_pull_requests_with_no_activity_40_days("#{options[:namespace]}/#{repo}")
  array_no_activity_pulls = array_no_activity_pulls + no_activity_pulls

  #failing tests
  bad_status_pulls = util.fetch_pull_requests_with_bad_status("#{options[:namespace]}/#{repo}")
  total_bad_status_pulls = total_bad_status_pulls + bad_status_pulls.size
  #needs squash
  squashed_pulls = util.fetch_pull_requests_which_need_squashed("#{options[:namespace]}/#{repo}")
  total_squashed_pulls = total_squashed_pulls + squashed_pulls.size
  #total open pulls
  total_repo_open_pulls = util.fetch_pull_requests("#{options[:namespace]}/#{repo}")
  total_open_pulls = total_open_pulls + total_repo_open_pulls.size
  #total unmerged
  total_repo_unmerged_pulls = util.fetch_unmerged_pull_requests("#{options[:namespace]}/#{repo}")
  total_unmerged_pulls = total_unmerged_pulls + total_repo_unmerged_pulls.size
  #total merged
  total_repo_merged_pulls = util.fetch_merged_pull_requests("#{options[:namespace]}/#{repo}")
  total_merged_pulls = total_merged_pulls + total_repo_merged_pulls.size

  puts "#{options[:namespace]}/#{repo}, #{last_comment_pulls.size}, #{rebase_pulls.size}, #{bad_status_pulls.size}, #{squashed_pulls.size}, #{uncommented_pulls.size}, #{total_repo_open_pulls.size}, #{total_mentioned_pulls}, #{no_activity_pulls.size}"
end

if options[:display_overview]
  CSV.open("overview.csv", "w") do |csv|
    csv << ["needs closed", "needs rebase", "fails tests", "needs squashed", "total PRs", "uncommented"]
    csv << [array_last_comment_pulls.size, total_rebase_pulls, total_bad_status_pulls, total_squashed_pulls, total_open_pulls, array_uncommented_pulls.size]
  end
  CSV.open("totals.csv", "w") do |csv|
    csv << ["total unmerged PRs", "total merged PRs", "total open PRs", "total uncommented open PRs"]
    csv << [total_unmerged_pulls, total_merged_pulls, total_open_pulls, array_uncommented_pulls.size]
  end
end

html = []
html.push("<html><title>PRs that Require Triage</title>")
html.push("<h1>PRs that Require Triage</h1>")

htmlchunk = tablecreation("PRs that have 0 comments:",array_uncommented_pulls)
html.push(htmlchunk)
htmlchunk = tablecreation("Last comment from puppet, no response for 15 days (needs ping):",array_needs_prompt_pulls)
html.push(htmlchunk)
htmlchunk = tablecreation("Last comment from puppet, no response for 30 days (needs closed):",array_last_comment_pulls)
html.push(htmlchunk)
htmlchunk = tablecreation("PRs that have yet to be commented on by a puppet member:",array_puppet_uncommented_pulls)
html.push(htmlchunk)
htmlchunk = tablecreation("PRs that community have asked for help (mentioned a puppet member):",array_mentioned_pulls)
html.push(htmlchunk)
htmlchunk = tablecreation("PRs that require rebase (needs comment and a label):",array_needs_rebase_no_label_pulls)
html.push(htmlchunk)
htmlchunk = tablecreation("PRs that require closing, no activity for 40 days:",array_no_activity_pulls)
html.push(htmlchunk)
html.push("</html>")

if options[:work]
  File.open("report.html", "w+") do |f|
    f.puts(html)
  end
end
