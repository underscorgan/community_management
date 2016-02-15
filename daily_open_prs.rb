#!/usr/bin/env ruby
#This script is to output a csv file to tally how many PRs are currently open on each day between two date ranges. It is also split into both PRs raised by community members and PRs raised by Puppet members.

require 'optparse'
require 'csv'
require 'octokit'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: open_and_created.rb [options]'

  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-o', '--overview', 'Output overview, summary totals to csv') { options[:display_overview] = true}

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

all_pulls = []
pr_cache = []

repos.each do |repo|

  #Retrieves all PRs for the repo
  pr_cache = (util.fetch_async("#{options[:namespace]}/#{repo}", search_with={:state => 'open'}, filter=[]))
  pr_cache.concat(util.fetch_async("#{options[:namespace]}/#{repo}", search_with={:state => 'closed'}, filter=[]))

  pr_cache.each do |pr|
    all_pulls.push (pr[:pull])
  end
end

puppet_members = {}
puppet_members = util.puppet_organisation_members(all_pulls)

#Defines the dates required
end_date = Time.now.to_date
start_date = end_date - 28

#Currently open per day
days = []
(start_date..end_date).each do |day_to_check|
  puppet_prs = 0
  community_prs = 0
  all_pulls.each do |pull|
    if pull[:state] == "closed"
      if (pull[:closed_at].to_date > day_to_check)
        if puppet_members.key?(pull.user[:login])
          puppet_prs += 1
        else
          community_prs += 1
        end
      end
    elsif pull[:state] == "open"
      if puppet_members.key?(pull.user[:login])
        puppet_prs += 1
      else
        community_prs += 1
      end
    end
  end
  row = {"date" => day_to_check.strftime('%F'), "puppet" => puppet_prs, "community" => community_prs}
  days.push(row)
  day_to_check += 1
end

#Creates the CSV file
CSV.open("daily_open_prs.csv", "w") do |csv|
  csv << ["date", "puppet", "community"]
  days.each do |day|
    csv << [day["date"], day["puppet"], day["community"]]
  end
end
