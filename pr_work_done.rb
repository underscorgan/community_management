#!/usr/bin/env ruby
# This script for every week will calculate:
# the number of closed prs
# the number of merged prs
# the number of comments made on prs

require 'optparse'
require 'csv'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: pr_work_done.rb [options]'

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

number_of_weeks_to_show = 10

def date_of_next(day)
  date  = Date.parse(day)
  delta = date > Date.today ? 0 : 7
  date + delta
end

#find next wedenesday, set boundries
right_bound = date_of_next "Wednesday"
left_bound = right_bound - 7
since = (right_bound - (number_of_weeks_to_show * 7))

all_merged_pulls = []
all_closed_pulls = []
comments = []
members_of_organisation = {}

#gather all commments / merges / closed in our time range (since)
repos.each do |repo|
  closed_pr_information_cache = util.fetch_async("#{options[:namespace]}/#{repo}", git_options={:state=>'closed'}, filter=[:issue_comments], limit={:attribute=>'closed_at', :date=>since})
  #closed prs
  all_closed_pulls.concat(util.fetch_unmerged_pull_requests(closed_pr_information_cache))
  #merged prs
  all_merged_pulls.concat(util.fetch_merged_pull_requests(closed_pr_information_cache))
  #find organisation members, if we havent already
  if members_of_organisation.size == 0
    members_of_organisation = util.puppet_organisation_members(all_merged_pulls)
  end
  #all comments made by organisation members
  closed_pr_information_cache.each do |pull|
    if pull[:issue_comments].size > 0 
      pull[:issue_comments].each do |comment| 
        if members_of_organisation.key?(comment.user.login)
          comments.push(comment)
        end
      end
    end
  end

  puts "repo #{repo}"
end

week_data = []
#for gathered comments / merges / closed, which week does it belong to
(0..number_of_weeks_to_show-1).each do |week_number|
  #find closed 
  closed = 0
  all_closed_pulls.each do |pull|
    if pull[:closed_at] < right_bound.to_time and pull[:closed_at] > left_bound.to_time
      closed +=1
    end
  end
  #find merged
  merged = 0
  all_merged_pulls.each do |pull|
    if pull[:closed_at] < right_bound.to_time and pull[:closed_at] > left_bound.to_time
      merged +=1
    end
  end
  #find commments from puppet
  comment_count = 0
  comments.each do |iter|
    if iter[:created_at] < right_bound.to_time and iter[:created_at] > left_bound.to_time
      comment_count +=1
    end
  end

  row = {"week ending on" => right_bound, "closed" => closed, "commented" => comment_count, "merged" => merged}
  week_data.push(row)
  #move boundries
  right_bound = left_bound
  left_bound = right_bound - 7
end 

#reverse week_data to give it in chronological order
week_data = week_data.reverse

CSV.open("pr_work_done.csv", "w") do |csv|
  csv << ["week ending on", "closed", "commented", "merged"]
  week_data.each do |week|
    csv << [week["week ending on"], week["closed"], week["commented"], week["merged"]]
  end
end
