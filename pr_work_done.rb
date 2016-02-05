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

number_of_weeks_to_show = 10

def date_of_next(day)
  date  = Date.parse(day)
  delta = date > Date.today ? 0 : 7
  date + delta
end

#find next wedenesday
right_boundry = date_of_next "Wednesday"
left_boundry = right_boundry - 7
merged_pulls = []
closed_pulls = []
comments = []
since = (right_boundry - (number_of_weeks_to_show * 7))
members = {}

repos.each do |repo|
  closed_pr_information_cache = util.fetch_async("#{options[:namespace]}/#{repo}", git_options={:state=>'closed'}, filter=[:issue_comments], limit={:attribute=>'closed_at', :date=>since})
  #total unmerged prs
  closed_pulls.concat(util.fetch_unmerged_pull_requests(closed_pr_information_cache))
  #total merged prs
  merged_pulls.concat(util.fetch_merged_pull_requests(closed_pr_information_cache))
  #all comments made by organisation members
  if members.size == 0
    members = util.puppet_organisation_members(merged_pulls)
  end
  closed_pr_information_cache.each do |pull|
    if pull[:issue_comments].size > 0 
      pull[:issue_comments].each do |comment| 
        if members.key?(comment.user.login)
          comments.push(comment)
        end
      end
    end
  end

  puts "repo #{repo}"
end

week = 0
weeks = []
while week < number_of_weeks_to_show do
  #find closed 
  closed = 0
  closed_pulls.each do |pull| 
    if pull[:closed_at] < right_boundry.to_time and pull[:closed_at] > left_boundry.to_time
      closed +=1
    end
  end
  #find merged
  merged = 0
  merged_pulls.each do |pull| 
    if pull[:closed_at] < right_boundry.to_time and pull[:closed_at] > left_boundry.to_time
      merged +=1
    end
  end
  #find commments from puppet
  comment_count = 0
  comments.each do |iter|
    if iter[:created_at] < right_boundry.to_time and iter[:created_at] > left_boundry.to_time
      comment_count +=1
    end
  end

  row = {"week ending on" => right_boundry, "closed" => closed, "commented" => comment_count, "merged" => merged}
  weeks.push(row)
  #move boundries
  right_boundry = left_boundry
  left_boundry = right_boundry - 7
  week +=1
end 

CSV.open("work_done.csv", "w") do |csv|
  csv << ["week ending on", "closed", "commented", "merged"]
  weeks.each do |week|
    csv << [week["week ending on"], week["closed"], week["commented"], week["merged"]]
  end
end
