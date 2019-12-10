#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'optparse'
require_relative 'octokit_utils'

class PuppetModule
  attr_accessor :name, :namespace, :tag_date, :commits, :downloads
  def initialize(name, namespace, tag_date, commits, downloads = 0)
    @name = name
    @namespace = namespace
    @tag_date = tag_date
    @commits = commits
    @downloads = downloads
  end
end

puppet_modules = []
def number_of_downloads(module_name)
  uri = URI.parse("https://forgeapi.puppetlabs.com/v3/modules/#{module_name}")
  request =  Net::HTTP::Get.new(uri.path)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http| # pay attention to use_ssl if you need it
    http.request(request)
  end
  output = response.body
  parsed = JSON.parse(output)
  puts parsed

  begin
    parsed['current_release']['downloads']
  rescue NoMethodError
    "Error number of downloads #{module_name}"
  end
end

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: release_planning.rb [options]'

  opts.on('-c', '--commit-threshold NUM', 'Number of commits since release') { |v| options[:commits] = v.to_i }
  opts.on('-g', '--tag-regex REGEX', 'Tag regex') { |v| options[:tag_regex] = v }
  opts.on('-m', '--time-threshold DAYS', 'Days since release') { |v| options[:time] = v.to_i }
  opts.on('-f', '--file NAME', String, 'Module file list') { |v| options[:file] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-v', '--verbose', 'More output') { options[:verbose] = true }
  opts.on('-o', '--output', 'Creates html+json output') { options[:output] = true }
end

parser.parse!

options[:file] = 'modules.json' if options[:file].nil?

missing = []
missing << '-t' if options[:oauth].nil?
missing << '-m or -c' if options[:time].nil? && options[:commits].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

options[:tag_regex] = '.*' if options[:tag_regex].nil?

util = OctokitUtils.new(options[:oauth])
parsed = util.load_module_list(options[:file])

repo_data = []

parsed.each do |m|
  begin
    latest_tag = util.fetch_tags("#{m['github_namespace']}/#{m['repo_name']}", options).first
    tag_ref = util.ref_from_tag(latest_tag)
    date_of_tag = util.date_of_ref("#{m['github_namespace']}/#{m['repo_name']}", tag_ref)
    commits_since_tag = util.commits_since_date("#{m['github_namespace']}/#{m['repo_name']}", date_of_tag)
    repo_data << { 'repo' => "#{m['github_namespace']}/#{m['repo_name']}", 'date' => date_of_tag, 'commits' => commits_since_tag, 'downloads' => number_of_downloads(m['forge_name']) }
    puppet_modules << PuppetModule.new(repo, "#{m['github_namespace']}/#{m['repo_name']}", date_of_tag, commits_since_tag)
  rescue StandardError
    puts "Unable to fetch tags for #{options[:namespace]}/#{repo}" if options[:verbose]
  end
end

puppet_modules.each { |puppet_module1| puts puppet_module1 }

due_by_commit = repo_data.select { |x| x['commits'] > options[:commits] } if options[:commits]

if options[:time]
  threshold = Time.now - options[:time]
  due_by_time = repo_data.select { |x| x['date'] < threshold }
end

due_for_release = if due_by_commit && due_by_time
                    due_by_commit & due_by_time
                  elsif due_by_commit
                    due_by_commit
                  else
                    due_by_time
                  end

due_for_release.each do |entry|
  puts "#{entry['repo']} is due for release. Last release was tagged on #{entry['date']} and there have been #{entry['commits']} commits since then."
end

html = ERB.new(File.read('release_planning.html.erb')).result(binding)

if options[:output]
  File.open('ModulesRelease.html', 'w+') do |f|
    f.puts(html)
  end

  File.open('ModulesRelease.json', 'w') do |f|
    JSON.dump(due_for_release, f)
  end
end
