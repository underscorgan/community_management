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
  opts.banner = 'Usage: stats.rb [options]'

  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
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

open_prs = []

def does_array_have_pr(array, pr_number)
  found = false
  array.each do |entry|
    found = true if pr_number == entry.number
  end
  found
end

parsed.each do |m|
  pr_information_cache = util.fetch_async("#{m['github_namespace']}/#{m['repo_name']}")
  # no comment from a puppet employee
  puppet_uncommented_pulls = util.fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
  # last comment mentions a puppet person
  mentioned_pulls = util.fetch_pull_requests_mention_member(pr_information_cache)

  # loop through open pr's and create a row that has all the pertinant info
  pr_information_cache.each do |pr|
    row = {}
    row[:repo] = m['repo_name']
    row[:address] = "https://github.com/#{m['github_namespace']}/#{m['repo_name']}"
    row[:pr] = pr[:pull].number
    row[:age] = ((Time.now - pr[:pull].created_at) / 60 / 60 / 24).round
    row[:owner] = pr[:pull].user.login
    row[:owner] += " <span class='label label-warning'>puppet</span>" if util.client.organization_member?('puppetlabs', pr[:pull].user.login)
    row[:owner] += " <span class='label label-primary'>vox</span>" if util.client.organization_member?('voxpupuli', pr[:pull].user.login)
    row[:title] = pr[:pull].title

    if !pr[:issue_comments].empty?
      row[:last_comment] = pr[:issue_comments].last.body
      row[:by] = pr[:issue_comments].last.user.login
      row[:age_comment] = ((Time.now - pr[:issue_comments].last.updated_at) / 60 / 60 / 24).round
    else
      row[:last_comment] = ''
      row[:by] = ''
      row[:age_comment] = 0
    end
    row[:num_comments] = pr[:issue_comments].size

    # find prs not commented by puppet
    row[:no_comment_from_puppet] = does_array_have_pr(puppet_uncommented_pulls, pr[:pull].number)
    # last comment mentions puppet member
    row[:last_comment_mentions_puppet] = does_array_have_pr(mentioned_pulls, pr[:pull].number)

    open_prs.push(row)
  end
end

html = []
html.push('<html><title>PRs that require review</title>')
html.push("<head><script src='./web_libraries/sorttable.js'></script><link rel='stylesheet' href='./web_libraries/bootstrap.min.css'></head>")
html.push('<body>')
html.push('<h1>PRs that require review</h1>')
html.push("<table border='1' style='width:100%' class='sortable table table-hover'> <tr>")
open_prs.first.keys.each do |header|
  html.push("<td>#{header}</td>") unless header == :address
end
html.push('</tr>')
open_prs.each do |row|
  html.push('<tr>')
  row.each do |key, value|
    if key == :pr
      html.push("<td><a href='#{row[:address]}/pull/#{value}'>#{value}</a></td>")
    elsif key == :repo
      html.push("<td><a href='#{row[:address]}'>#{value}</a></td>")
    else
      html.push("<td>#{value}</td>") unless key == :address
    end
  end
  html.push('</tr>')
end
html.push('</table>')
open_prs.each do |row|
  puts(row)
end

File.open('report.html', 'w+') do |f|
  f.puts(html)
end

File.open('report.json', 'w') do |f|
  JSON.dump(open_prs, f)
end
