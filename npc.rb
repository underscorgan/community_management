#!/usr/bin/env ruby

require 'optparse'
require_relative 'octokit_utils'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: npc.rb [options]'

  opts.on('-n', '--namespace NAME', 'GitHub namespace. Required.') { |v| options[:namespace] = v }
  opts.on('-r', '--repo-regex REGEX', 'Repository regex') { |v| options[:repo_regex] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
  opts.on('-m', '--merge-conflicts', 'Comment / label PRs that have merge conflicts') { options[:merge_conflicts] = true}
  opts.on('-N', '--no-op', 'No-op, dont actually edit the PRs') { options[:no_op] = true}

  # default filters
  opts.on('--puppetlabs', 'Select Puppet Labs\' modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = '^puppetlabs-'
  }

  opts.on('--puppetlabs-supported', 'Select only Puppet Labs\' supported modules') {
    options[:namespace] = 'puppetlabs'
    options[:repo_regex] = '^puppetlabs-(acl|apache|apt|aws|catalog_preview|concat|docker_platform|f5|firewall|haproxy|inifile|java|java_ks|mysql|netscaler|ntp|postgresql|powershell|reboot|registry|sqlserver|stdlib|tomcat|vcsrepo)$'
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

if options[:no_op]
  puts "RUNNING IN NO-OP MODE"
else
  puts "MAKING CHANGES TO YOUR REPOS"
end

util = OctokitUtils.new(options[:oauth])
repos = util.list_repos(options[:namespace], options)

repos.each do |repo|
  if options[:merge_conflicts]
    prs = util.fetch_pull_requests("#{options[:namespace]}/#{repo}")
    prs.each do |pr|
      #do we already have a label ?
      pr_merges = util.does_pr_merge("#{options[:namespace]}/#{repo}", pr.number)
      pr_has_label = util.does_pr_have_label("#{options[:namespace]}/#{repo}", pr.number, "needs-rebase")
      unless pr_merges 
        # pr does not merge
        unless pr_has_label
          #pr does not have a label
          puts "#{options[:namespace]}/#{repo} #{pr.number} adding comment and label"
          unless options[:no_op]
            #do comment
            util.add_comment_to_pr("#{options[:namespace]}/#{repo}", pr.number, "Thanks @#{pr.user.login} for your work, but can't be merged as it has conflicts. Please rebase them on the current master, fix the conflicts and repush here. https://git-scm.com/book/en/v2/Git-Branching-Rebasing")
            #do label
            util.add_label_to_pr("#{options[:namespace]}/#{repo}", pr.number, "needs-rebase")
          end
        else
          #has label
          puts "#{options[:namespace]}/#{repo} #{pr.number} already labeled"
        end
      else
        #pr merges
        #we have a label. should we remove the label if it is mergable
        if pr_has_label 
          puts "#{options[:namespace]}/#{repo} #{pr.number} removing label"
          unless options[:no_op]
            util.remove_label_from_pr("#{options[:namespace]}/#{repo}", pr.number, "needs-rebase")
          end
        end
      end
    end
  end
end
