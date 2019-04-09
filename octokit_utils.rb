#!/usr/bin/env ruby

require 'octokit'

class OctokitUtils
  attr_accessor :client

  SUPPORTED_MODULES = [
    'accounts',
    'apache',
    'apt',
    'bootstrap',
    'concat',
    'exec',
    'facter_task',
    'firewall',
    'haproxy',
    'hocon',
    'ibm_installation_manager',
    'inifile',
    'java_ks',
    'java',
    'motd',
    'mysql',
    'ntp',
    'package',
    'postgresql',
    'puppet_conf',
    'reboot',
    'resource',
    'satellite_pe_tools',
    'service',
    'stdlib',
    'tagmail',
    'tomcat',
    'translate',
    'vcsrepo',
    'vsphere',
    'websphere_application_server',
    'docker',
    'helm',
    'kubernetes',
    'rook',
    'amazon_aws',
    'azure_arm',
    'acl',
    'chocolatey',
    'dsc',
    'dsc_lite',
    'iis',
    'powershell',
    'reboot',
    'registry',
    'scheduled_task',
    'sqlserver',
    'wsus_client',
  ]

  SUPPORTED_MODULES_REGEX = "^(puppetlabs-(#{SUPPORTED_MODULES.join('|')})|modulesync_configs)$"

  def initialize(access_token)
    Octokit.auto_paginate = true
    @client = Octokit::Client.new(:access_token => "#{access_token}")
    client.user.login

    @pr_cache = {}
  end

  def list_repos(organization, options)
    if not options[:repo_regex]
      regex = '.*'
    else
      regex = options[:repo_regex]
    end

    repos ||= client.organization_repositories(organization).collect {|org| org[:name] if org[:name] =~ /#{regex}/}
    # The collection leaves nil entries in for non-matches
    repos = repos.select {|repo| repo }
    return repos.sort.uniq
  end

  def pulls(repo, options)
    @pr_cache[[repo, options]] ||= client.pulls(repo, options)
  end

  def fetch_async(repo, options={:state=>'open', :sort=>'updated'}, filter=[:statuses, :pull_request_commits, :issue_comments], limit=nil)
  #example of limit..  limit={:attribute=>'closed_at', :date=>'2016-01-15 12:59:47 UTC'}
    pr_information_cache = []
    prs = []
    unlimited_prs = client.pulls(repo, options)

    #there can be a large number of PRs returned, this limits the date range we are looking in
    if limit.nil?
      prs = unlimited_prs
    else
      unlimited_prs.each do |iter|
        if limit[:attribute] == 'closed_at'
          if iter.closed_at > limit[:date].to_time
            prs.push(iter)
          end
        end
      end
    end

    poolsize = 10
    mutex = Mutex.new

    poolsize.times.map {
      Thread.new(prs, pr_information_cache) do |prs, pr_information_cache|
        while pr = mutex.synchronize { prs.pop }
          pr_information = fetch_pr_information(repo, pr, filter)
          mutex.synchronize { pr_information_cache << pr_information }
        end
      end
    }.each(&:join)
    return pr_information_cache
  end

  def fetch_pr_information(repo, pr, filter=[:statuses, :pull_request_commits, :issue_comments, :pull_request])
    returnVal = {}
    returnVal[:pull] = pr
    if filter.include? :statuses
      returnVal[:statuses] = client.statuses(repo, pr.head.sha)
    end
    if filter.include? :pull_request_commits
      returnVal[:pull_request_commits] = client.pull_request_commits(repo, pr.number)
    end
    if filter.include? :pull_request
      returnVal[:pull_request] = client.pull_request(repo, pr.number)
    end
    if filter.include? :issue_comments
      returnVal[:issue_comments] = client.issue_comments(repo, pr.number)
    end

    returnVal
  end

  def fetch_pull_requests_with_bad_status(pr_information_cache)
    returnVal = []
    pr_information_cache.each do |pr|
      status = pr[:statuses]
      if status.first != nil and status.first.state != 'success'
          returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_pull_requests_which_need_squashed(pr_information_cache)
    returnVal = []
    pr_information_cache.each do |pr|
      commits = pr[:pull_request_commits]
      if commits.size > 1
        returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_pull_requests(repo, options={:state=>'open', :sort=>'updated'})
    pulls(repo, options)
  end

  def fetch_merged_pull_requests(pr_information_cache)
    returnVal = []
    pr_information_cache.each do |pr|
      if pr[:pull].merged_at != nil
        returnVal.push (pr[:pull])
      end
    end
    returnVal
  end

  def fetch_pull_requests_with_no_activity_40_days(pr_information_cache)
    returnVal = []
    boundry = (DateTime.now - 40).to_time
    pr_information_cache.each do |pr|
      if  pr[:pull].updated_at < boundry
        returnVal.push (pr[:pull])
      end
    end
    returnVal
  end

  def fetch_uncommented_pull_requests(pr_information_cache)
    returnVal = []
    pr_information_cache.each do |pr|
      size = pr[:issue_comments].size
      if size == 0
        returnVal.push (pr[:pull])
      end
    end
    returnVal
  end

  def fetch_unmerged_pull_requests(pr_information_cache)
    returnVal = []
    pr_information_cache.each do |pr|
      if pr[:pull].merged_at == nil
        returnVal.push (pr[:pull])
      end
    end
    returnVal
  end

  def fetch_pull_requests_which_need_rebase(pr_information_cache)
    returnVal = []
    pr_information_cache.each do |pr|
      state = pr[:pull_request]
        if state.mergeable  == false
        returnVal.push pr[:pull]
      end
    end
    returnVal
  end

  def fetch_pull_requests_with_last_owner_comment(pr_information_cache)
    prs = []
    pr_information_cache.each do |iter|
      prs.push iter[:pull]
    end
    return [] if prs.empty?

    members = puppet_organisation_members(prs)
    returnVal =  []
    pr_information_cache.each do |iter|
      if iter[:issue_comments].size > 0 && members.key?(iter[:issue_comments].last.user.login)
        returnVal.push(iter[:pull])
      end
    end

    returnVal
  end

  def fetch_pull_requests_mention_member(pr_information_cache)
    prs = []
    pr_information_cache.each do |iter|
      prs.push iter[:pull]
    end
    return [] if prs.empty?
    returnVal = []
    members = puppet_organisation_members(prs)

    pr_information_cache.each do |pr|
      comments = pr[:issue_comments]
      unless comments.empty?
        comments.last.body.gsub(/@\w*/) do |person|
          #remove @
          person[0] = ''
          if members.has_key?(person)
            returnVal.push(pr[:pull]) unless returnVal.include?(pr[:pull])
          end
        end
      end
    end

    returnVal
  end

  def fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
    prs = []
    pr_information_cache.each do |iter|
      prs.push iter[:pull]
    end
    return [] if prs.empty?
    returnVal = []
    members = puppet_organisation_members(prs)

    pr_information_cache.each do |iter|
      commenters = []
      iter[:issue_comments].each do |comment|
        commenters.push(comment.user.login)
      end

      member_array = members.keys
      if (member_array & commenters).empty?
        returnVal.push(iter[:pull])
      end
    end
    returnVal
  end

  def puppet_organisation_members(prs)
    owner = prs.first.base.repo.owner
    if owner.type == 'User'
      members = { owner.login => :owner }
    else
      members = client.organization_members(owner.login).each_with_object({}) { |user, hash| hash[user.login] = :owner }
    end
    members
  end

  def self.sort_pulls(prs)
    prs.sort do |a, b|
      result = a.base.repo.name <=> b.base.repo.name
      result = a.number <=> b.number if result == 0
      result
    end
  end

  def pulls_newer_than(time, options)
    if not options[:pulls] and not options[:repo]
      raise ArgumentError, 'One of :pulls or :repo must be specified in the options hash'
    end
    if not options[:pulls]
      pulls=fetch_pull_requests(options[:repo])
    else
      pulls=options[:pulls]
    end
    pulls.select { |pull| pull[:updated_at] > time }
  end

  def pulls_older_than(time, options)
    if not options[:pulls] and not options[:repo]
      raise ArgumentError, 'One of :pulls or :repo must be specified in the options hash'
    end
    if not options[:pulls]
      pulls=fetch_pull_requests(options[:repo])
    else
      pulls=options[:pulls]
    end
    pulls.select { |pull| pull[:updated_at] < time }
  end

  def pulls_in_range(start_time, end_time, options)
    if not options[:pulls] and not options[:repo]
      raise ArgumentError, 'One of :pulls or :repo must be specified in the options hash'
    end
    if not options[:pulls]
      pulls=fetch_pull_requests(options[:repo])
    else
      pulls=options[:pulls]
    end
    pulls.select{ |pull| pull[:updated_at] < end_time and pull[:updated_at] > start_time }
  end

  def fetch_tags(repo, options)
    if not options[:tag_regex]
      regex = '.*'
    else
      regex = options[:tag_regex]
    end

    tags ||= client.tags(repo)
    tags.select {|tag| tag[:name] =~ /#{regex}/}
  end

  def ref_from_tag(tag)
    tag[:commit][:sha]
  end

  def date_of_ref(repo, ref)
    commit ||= client.commit(repo, ref)
    commit[:commit][:author][:date]
  end

  def commits_since_date(repo, date)
    commits ||= client.commits_since(repo, date)
    commits.size
  end

  def test_for_release(repo, options)
    if not options[:commits] and not options[:time]
      raise ArgumentError, 'One of :commits or :time must be specified in the options hash'
    end

    newest_tag = fetch_tags(repo, options).first
    if newest_tag
      date_of_tag = date_of_ref(repo, ref_from_tag(newest_tag)).to_dateime
      if options[:time] and date_of_tag < (DateTime.now - options[:time])
        if options[:commits] and (client.commits(repo, since: date_of_tag).count > options[:commits])
          puts "#{repo}: A new release is needed"
        else
          puts "#{repo}: A new release is needed"
        end
      elsif not options[:time] and (client.commits(repo, since: date_of_tag).count > options[:commits])
        puts "#{repo}: A new release is needed"
      end
      #else?
    end
  end

  def format_pulls(pulls)
    pulls.each do |pull|
      repo = pull.repo.full_name
      updated_at = pull.updated_at
      url = pull.url
      number = pull.number
      puts "#{repo},#{updated_at},#{number},#{url}"
    end
  end

  def fetch_repo_missing_labels(repo, required_labels)
    returnVal = []
    repo_labels = []
    labels_data = client.labels(repo, {})

    labels_data.each do |label|
      repo_labels.push (label.name)
    end

    required_labels.each do |required_label|
      unless repo_labels.include?(required_label[:name])
        returnVal.push (required_label)
      end
    end
    returnVal
  end

  def fetch_repo_incorrect_labels(repo, required_labels)
    client.labels(repo, {}).map do |label|
      matching_label = required_labels.find { |l| l[:name] == label.name }
      if matching_label and matching_label[:color] != label.color
        { :name => label.name, :color => matching_label[:color] }
      else
        nil
      end
    end.compact
  end

  def fetch_repo_extra_labels(repo, required_labels)
    repo_labels = client.labels(repo, {}).map(&:name)
    keep_labels = required_labels.collect.map { |l| l[:name] }

    repo_labels.each_with_object([]) do |existing_label, memo|
      memo.push existing_label unless keep_labels.include?(existing_label)
    end
  end

  def add_repo_labels(repo, required_labels)
    required_labels.each do |required_label|
      client.add_label(repo, required_label[:name], required_label[:color])
    end
  end

  def update_repo_labels(repo, incorrect_labels)
    incorrect_labels.each do |incorrect_label|
      client.update_label(repo, incorrect_label[:name], { :color => incorrect_label[:color] })
    end
  end

  def delete_repo_labels(repo, extra_labels)
    extra_labels.each do |extra_label|
      client.delete_label!(repo, extra_label)
    end
  end

  def add_label_to_pr(repo, pr_number, label)
    client.add_labels_to_an_issue(repo, pr_number, [label])
  end

  def remove_label_from_pr(repo, pr_number, label)
    client.remove_label(repo, pr_number, label, {})
  end

  def add_comment_to_pr(repo, pr_number, comment)
    client.add_comment(repo, pr_number, comment)
  end

  def does_pr_have_label (repo, pr_number, needed_label)
    returnVal = false
    labels = client.labels_for_issue(repo, pr_number)
    labels.each do |label|
      if label.name == needed_label
        returnVal = true
      end
    end
    returnVal
  end

  def does_pr_merge (repo, pr_number)
    returnVal = false
    pr = client.pull_request(repo, pr_number, {})
    returnVal =  pr.mergeable
    returnVal
  end
end
