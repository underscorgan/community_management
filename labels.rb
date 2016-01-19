#!/usr/bin/env ruby

require 'optparse'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: labels.rb [options]'

  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-f', '--fix-labels', 'Add the missing labels to repo') { options[:fix_labels] = true}

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

wanted_labels = [{:name=>'needs-squash', :color=>'bfe5bf'}, {:name=>'needs-rebase', :color=>'207de5'}, {:name=>'needs-tests', :color=>'f7c6c7'}, {:name=>'needs-docs', :color=>'006b75'}, {:name=>'bugfix', :color=>'009800'}, {:name=>'feature', :color=>'0052cc'}, {:name=>'tests-fail', :color=>'e11d21'}, {:name=>'backwards-incompatible', :color=>'eb6420'}]

label_names = []
wanted_labels.each do |wanted_label|
  label_names.push (wanted_label[:name])
end
puts "Checking for the following labels: #{label_names}"

repos.each do |repo|
  missing_labels = util.fetch_repo_missing_labels("#{options[:namespace]}/#{repo}", wanted_labels)
  puts "#{options[:namespace]}/#{repo}, #{missing_labels}" 
  if options[:fix_labels]
    util.add_repo_labels("#{options[:namespace]}/#{repo}", missing_labels)
  end
end
