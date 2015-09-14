#!/usr/bin/env ruby

require 'octokit'

class OctokitUtils
  attr_accessor :client

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

  def fetch_pull_requests_with_bad_status(repo, options={:state=>'open', :sort=>'updated'})
    returnVal = []
    pulls(repo, options).each do |pr|
      status = client.statuses(repo, pr.head.sha)
      if status.first != nil and status.first.state != 'success'
          returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_pull_requests_which_need_squashed(repo, options={:state=>'open', :sort=>'updated'})
    returnVal = []
    pulls(repo, options).each do |pr|
      commits = client.pull_request_commits(repo, pr.number)
      if commits.size > 1
        returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_pull_requests(repo, options={:state=>'open', :sort=>'updated'})
    pulls(repo, options)
  end

  def fetch_merged_pull_requests(repo, options={:state=>'closed', :sort=>'updated'})
    returnVal = []
    pulls(repo, options).each do |pr|
      if pr.merged_at != nil
        returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_uncommented_pull_requests(repo, options={:state=>'open', :sort=>'updated'})
    returnVal = []
    pulls(repo, options).each do |pr|
      size = client.issue_comments(repo, pr.number, options).size
      if size == 0
        returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_unmerged_pull_requests(repo, options={:state=>'closed', :sort=>'updated'})
    returnVal = []
    pulls(repo, options).each do |pr|
      if pr.merged_at == nil
        returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_pull_requests_which_need_rebase(repo, options={:state=>'open', :sort=>'updated'})
    returnVal = []
    pulls(repo, options).each do |pr|
      status = client.pull_request(repo, pr.number, options)
      if status.mergeable == false
        returnVal.push (pr)
      end
    end
    returnVal
  end

  def fetch_pull_requests_with_last_owner_comment(repo, options={:state=>'open', :sort=>'updated'})
    prs ||= pulls(repo, options)
    return [] if prs.empty?

    members = puppet_organisation_members(prs)

    latest_comment_by_pr = client.issues_comments(repo, {:sort=> 'updated', :direction => 'desc'}).each_with_object({}) do |c, hash|
      hash[c.issue_url] ||= c
    end

    prs = prs.select do |p|
      latest_comment_by_pr[p.issue_url] && members[latest_comment_by_pr[p.issue_url].user.login] == :owner
    end

    prs
  end

  def fetch_pull_requests_with_no_puppet_personnel_comments(repo, options={:state=>'open', :sort=>'updated'})
    returnVal = []

    prs = pulls(repo, options)
    return [] if prs.empty?

    members = puppet_organisation_members(prs)
    prs.each do |pr|
      commenters = []
      client.issue_comments(repo, pr.number).each do |comment|
        commenters.push(comment.user.login)
      end

      member_array = members.keys
      if (member_array & commenters).empty?
        returnVal.push(pr)
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

  def add_repo_labels(repo, required_labels)
    required_labels.each do |required_label|
      client.add_label(repo, required_label[:name], required_label[:color])
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
