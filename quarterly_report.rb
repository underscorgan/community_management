#!/usr/bin/env ruby
#This script is for discovering quarterly metrics of PRs in total. How many are created, closed and merged by community members in a specified quarter.

require 'optparse'
require 'csv'
require 'octokit'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: quarterly_report.rb [options]'

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
  opts.on('--voxpupuli', 'Select puppet voxpupuli modules') {
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

puppet_members = ["bmjen", "HelenCampbell", "hunner", "DavidS", "tphoney", "jonnytpuppet", "garethr", "gregohardy", "mentat"]
quarter_begin = Date.new(2015,11,01)
quarter_end = Date.new(2016,01,31)
quarter_begin = quarter_begin.to_time
quarter_end = quarter_end.to_time
created = 0
merged = 0
closed = 0

all_pulls.each do |pull|
  if (!puppet_members.include?(pull.user[:login]))
    if pull[:created_at] > quarter_begin and pull[:created_at] < quarter_end
      created = created + 1
    end
    #require 'pry'; binding.pry
    if !pull[:merged_at].nil? 
      if pull[:merged_at] > quarter_begin and pull[:merged_at] < quarter_end
        merged = merged + 1
      end
    elsif !pull[:closed_at].nil?
      if pull[:closed_at] > quarter_begin and pull[:closed_at] < quarter_end
        closed = closed + 1
      end
    end
  end
end
puts created
puts merged
puts closed
