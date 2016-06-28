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
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }

  # default filters
  opts.on('--puppetlabs', 'Select Puppet Labs\' modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = '^puppetlabs-'
  }

  opts.on('--puppetlabs-supported', 'Select only Puppet Labs\' supported modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = OctokitUtils::SUPPORTED_MODULES_REGEX
  }

  opts.on('--voxpupuli', 'Select Voxpupuli modules') {
    options[:namespace] = 'voxpupuli'
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

open_prs = []

def does_array_have_pr(array, pr_number)
  found = false
  array.each do |entry|
    if pr_number == entry.number
      found = true
    end
  end
  found
end

repos.each do |repo|
  pr_information_cache = util.fetch_async("#{options[:namespace]}/#{repo}", search_with={:state=>'open', :sort=>'updated'}, filter=[:statuses, :pull_request_commits, :issue_comments, :pull_request])
  #no comment from a puppet employee
  puppet_uncommented_pulls = util.fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
  #last comment mentions a puppet person
  mentioned_pulls = util.fetch_pull_requests_mention_member(pr_information_cache)

  # loop through open pr's and create a row that has all the pertinant info
  pr_information_cache.each do |pr|
    row = {}
    row[:repo] = repo
    row[:pr] = pr[:pull].number
    row[:age] = ((Time.now - pr[:pull].created_at) / 60 / 60 / 24).round
    row[:owner] = pr[:pull].user.login
    row[:title] = pr[:pull].title

    if pr[:issue_comments].size > 0 
      row[:last_comment] = pr[:issue_comments].last.body
      row[:by] = pr[:issue_comments].last.user.login
      row[:age_comment] = ((Time.now - pr[:issue_comments].last.updated_at) / 60 / 60 / 24).round
    else
      row[:last_comment] = ""
      row[:by] = ""
      row[:age_comment] = 0
    end
    row[:num_comments] = pr[:issue_comments].size

    #find prs not commented by puppet
    row[:no_comment_from_puppet] = does_array_have_pr(puppet_uncommented_pulls, pr[:pull].number)
    #last comment mentions puppet member
    row[:last_comment_mentions_puppet] = does_array_have_pr(mentioned_pulls, pr[:pull].number)

    open_prs.push(row)
  end
end

html = []
html.push("<html><title>PRs that require review</title>")
html.push("<head><script src='./web_libraries/sorttable.js'></script><link rel='stylesheet' href='./web_libraries/bootstrap.min.css'></head>")
html.push("<body>")
html.push("<h1>PRs that require review</h1>")
html.push("<table border='1' style='width:100%' class='sortable table table-hover'> <tr>")
open_prs.first.keys.each do |header|
  html.push("<td>#{header}</td>")
end
html.push("</tr>")
open_prs.each do |row|
  html.push("<tr>")
  row.each do |key, value|
    unless key == :pr
      html.push("<td>#{value}</td>")
    else
      repo_name = row[:repo]
      html.push("<td><a href='https://github.com/#{options[:namespace]}/#{repo_name}/pull/#{value}'>#{value}</a></td>")
    end
  end
  html.push("</tr>")
end
html.push("</table>")
open_prs.each do |row|
  puts(row)
end

File.open("report.html", "w+") do |f|
  f.puts(html)
end
