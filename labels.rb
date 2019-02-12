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
  opts.on('-d', '--delete-labels', 'Delete unwanted labels from repo') { options[:delete_labels] = true }

  # default filters
  opts.on('--puppetlabs', 'Select Puppet Labs\' modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = '^puppetlabs-'
  }

  opts.on('--puppetlabs-supported', 'Select only Puppet Labs\' supported modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = OctokitUtils::SUPPORTED_MODULES_REGEX
  }

  opts.on('--voxpupuli', 'Select voxpupuli modules') {
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

wanted_labels = [{:name=>'needs-squash', :color=>'bfe5bf'}, {:name=>'needs-rebase', :color=>'3880ff'}, {:name=>'needs-tests', :color=>'ff8091'}, {:name=>'needs-docs', :color=>'149380'}, {:name=>'bugfix', :color=>'00d87b'}, {:name=>'feature', :color=>'222222'}, {:name=>'tests-fail', :color=>'e11d21'}, {:name=>'backwards-incompatible', :color=>'d63700'}, {:name=>'maintenance', :color=>'ffd86e'}]

label_names = []
wanted_labels.each do |wanted_label|
  label_names.push (wanted_label[:name])
end
puts "Checking for the following labels: #{label_names}"

repos.each do |repo|
  repo_name = "#{options[:namespace]}/#{repo}"
  missing_labels = util.fetch_repo_missing_labels(repo_name, wanted_labels)
  incorrect_labels = util.fetch_repo_incorrect_labels(repo_name, wanted_labels)
  extra_labels = util.fetch_repo_extra_labels(repo_name, wanted_labels)
  puts "Delete: #{repo_name}, #{extra_labels}"
  puts "Create: #{repo_name}, #{missing_labels}"
  puts "Fix: #{repo_name}, #{incorrect_labels}"
  if options[:delete_labels]
    util.delete_repo_labels(repo_name, extra_labels) unless extra_labels.empty?
  end
  if options[:fix_labels]
    util.update_repo_labels(repo_name, incorrect_labels) unless incorrect_labels.empty?
    util.add_repo_labels(repo_name, missing_labels) unless missing_labels.empty?
  end
end
