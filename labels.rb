#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: labels.rb [options]'
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-f', '--fix-labels', 'Add the missing labels to repo') { options[:fix_labels] = true }
  opts.on('-d', '--delete-labels', 'Delete unwanted labels from repo') { options[:delete_labels] = true }
  opts.on('-f', '--file NAME', String, 'Module file list') { |v| options[:file] = v }
end

parser.parse!
options[:file] = 'modules.json' if options[:file].nil?

missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

util = OctokitUtils.new(options[:oauth])

wanted_labels = [{ name: 'needs-squash', color: 'bfe5bf' }, { name: 'needs-rebase', color: '3880ff' }, { name: 'needs-tests', color: 'ff8091' }, { name: 'needs-docs', color: '149380' }, { name: 'bugfix', color: '00d87b' }, { name: 'feature', color: '222222' }, { name: 'tests-fail', color: 'e11d21' }, { name: 'backwards-incompatible', color: 'd63700' }, { name: 'maintenance', color: 'ffd86e' }]
parsed = util.load_module_list(options[:file])

label_names = []
wanted_labels.each do |wanted_label|
  label_names.push(wanted_label[:name])
end
puts "Checking for the following labels: #{label_names}"

parsed.each do |m|
  repo_name = "#{m['github_namespace']}/#{m['repo_name']}"
  missing_labels = util.fetch_repo_missing_labels(repo_name, wanted_labels)
  incorrect_labels = util.fetch_repo_incorrect_labels(repo_name, wanted_labels)
  extra_labels = util.fetch_repo_extra_labels(repo_name, wanted_labels)
  puts "Delete: #{repo_name}, #{extra_labels}"
  puts "Create: #{repo_name}, #{missing_labels}"
  puts "Fix: #{repo_name}, #{incorrect_labels}"

  if options[:delete_labels]
    util.delete_repo_labels(repo_name, extra_labels) unless extra_labels.empty?
  end
  next unless options[:fix_labels]

  util.update_repo_labels(repo_name, incorrect_labels) unless incorrect_labels.empty?
  util.add_repo_labels(repo_name, missing_labels) unless missing_labels.empty?
end
