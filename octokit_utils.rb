#!/usr/bin/env ruby
# frozen_string_literal: true

require 'octokit'
require 'json'

class OctokitUtils
  attr_accessor :client

  def initialize(access_token)
    Octokit.auto_paginate = true
    @client = Octokit::Client.new(access_token: access_token.to_s)
    client.user.login

    @pr_cache = {}
  end

  # Octokit uses a different method for getting the repositories of an
  # orginazation than it does for getting the repositories of a user. This
  # method checks the "type" of a given namespace and uses the value to
  # determine the method to call.

  def list_repos(namespace, options)
    regex = if !(options[:repo_regex])
              '.*'
            else
              options[:repo_regex]
            end
    repos ||= ns_repos(namespace).collect { |ns_repo| ns_repo[:name] if ns_repo[:name] =~ /#{regex}/ }
    # The collection leaves nil entries in for non-matches
    repos = repos.select { |repo| repo }
    repos.sort.uniq
  end

  def pulls(repo, options)
    @pr_cache[[repo, options]] ||= client.pulls(repo, options)
  end

  def fetch_async(repo, options = { state: 'open', sort: 'updated' }, filter = %i[statuses pull_request_commits issue_comments], limit = nil)
    # example of limit..  limit={:attribute=>'closed_at', :date=>'2016-01-15 12:59:47 UTC'}
    pr_information_cache = []
    prs = []
    unlimited_prs = client.pulls(repo, options)

    # there can be a large number of PRs returned, this limits the date range we are looking in
    if limit.nil?
      prs = unlimited_prs
    else
      unlimited_prs.each do |iter|
        next unless limit[:attribute] == 'closed_at'

        prs.push(iter) if iter.closed_at > limit[:date].to_time
      end
    end

    poolsize = 10
    mutex = Mutex.new

    poolsize.times.map do
      Thread.new(prs, pr_information_cache) do |prs1, pr_information_cache1|
        while (pr = mutex.synchronize { prs1.pop })
          pr_information = fetch_pr_information(repo, pr, filter)
          mutex.synchronize { pr_information_cache1 << pr_information }
        end
      end
    end.each(&:join)
    pr_information_cache
  end

  def fetch_pr_information(repo, pull_request, filter = %i[statuses pull_request_commits issue_comments pull_request])
    return_val = {}
    return_val[:pull] = pull_request
    return_val[:statuses] = client.statuses(repo, pull_request.head.sha) if filter.include? :statuses
    return_val[:pull_request_commits] = client.pull_request_commits(repo, pull_request.number) if filter.include? :pull_request_commits
    return_val[:pull_request] = client.pull_request(repo, pull_request.number) if filter.include? :pull_request
    return_val[:issue_comments] = client.issue_comments(repo, pull_request.number) if filter.include? :issue_comments

    return_val
  end

  def fetch_pull_requests_with_bad_status(pr_information_cache)
    return_val = []
    pr_information_cache.each do |pr|
      status = pr[:statuses]
      return_val.push pr if !status.first.nil? && (status.first.state != 'success')
    end
    return_val
  end

  def fetch_pull_requests_which_need_squashed(pr_information_cache)
    return_val = []
    pr_information_cache.each do |pr|
      commits = pr[:pull_request_commits]
      return_val.push pr if commits.size > 1
    end
    return_val
  end

  def fetch_pull_requests(repo, options = { state: 'open', sort: 'updated' })
    pulls(repo, options)
  end

  def fetch_merged_pull_requests(pr_information_cache)
    return_val = []
    pr_information_cache.each do |pr|
      return_val.push(pr[:pull]) unless pr[:pull].merged_at.nil?
    end
    return_val
  end

  def fetch_pull_requests_with_no_activity_40_days(pr_information_cache)
    return_val = []
    boundry = (DateTime.now - 40).to_time
    pr_information_cache.each do |pr|
      return_val.push(pr[:pull]) if pr[:pull].updated_at < boundry
    end
    return_val
  end

  def fetch_uncommented_pull_requests(pr_information_cache)
    return_val = []
    pr_information_cache.each do |pr|
      size = pr[:issue_comments].size
      return_val.push(pr[:pull]) unless size.zero?
    end
    return_val
  end

  def fetch_unmerged_pull_requests(pr_information_cache)
    return_val = []
    pr_information_cache.each do |pr|
      return_val.push(pr[:pull]) if pr[:pull].merged_at.nil?
    end
    return_val
  end

  def fetch_pull_requests_which_need_rebase(pr_information_cache)
    return_val = []
    pr_information_cache.each do |pr|
      state = pr[:pull_request]
      return_val.push pr[:pull] if state.mergeable == false
    end
    return_val
  end

  def fetch_pull_requests_with_last_owner_comment(pr_information_cache)
    prs = []
    pr_information_cache.each do |iter|
      prs.push iter[:pull]
    end
    return [] if prs.empty?

    members = puppet_organisation_members(prs)
    return_val = []
    pr_information_cache.each do |iter|
      return_val.push(iter[:pull]) if !iter[:issue_comments].empty? && members.key?(iter[:issue_comments].last.user.login)
    end

    return_val
  end

  def fetch_pull_requests_mention_member(pr_information_cache)
    prs = []
    pr_information_cache.each do |iter|
      prs.push iter[:pull]
    end
    return [] if prs.empty?

    return_val = []
    members = puppet_organisation_members(prs)

    pr_information_cache.each do |pr|
      comments = pr[:issue_comments]
      next if comments.empty?

      comments.last.body.gsub(/@\w*/) do |person|
        # remove @
        person[0] = ''
        if members.key?(person)
          return_val.push(pr[:pull]) unless return_val.include?(pr[:pull])
        end
      end
    end

    return_val
  end

  def fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
    prs = []
    pr_information_cache.each do |iter|
      prs.push iter[:pull]
    end
    return [] if prs.empty?

    return_val = []
    members = puppet_organisation_members(prs)

    pr_information_cache.each do |iter|
      commenters = []
      iter[:issue_comments].each do |comment|
        commenters.push(comment.user.login)
      end

      member_array = members.keys
      return_val.push(iter[:pull]) if (member_array & commenters).empty?
    end
    return_val
  end

  def puppet_organisation_members(prs)
    owner = prs.first.base.repo.owner
    members = if owner.type == 'User'
                { owner.login => :owner }
              else
                client.organization_members(owner.login).each_with_object({}) { |user, hash| hash[user.login] = :owner }
              end
    members
  end

  def self.sort_pulls(prs)
    prs.sort do |a, b|
      result = a.base.repo.name <=> b.base.repo.name
      result = a.number <=> b.number if result.zero?
      result
    end
  end

  def pulls_newer_than(time, options)
    raise ArgumentError, 'One of :pulls or :repo must be specified in the options hash' if !(options[:pulls]) && !(options[:repo])

    pulls = if !(options[:pulls])
              fetch_pull_requests(options[:repo])
            else
              options[:pulls]
            end
    pulls.select { |pull| pull[:updated_at] > time }
  end

  def pulls_older_than(time, options)
    raise ArgumentError, 'One of :pulls or :repo must be specified in the options hash' if !(options[:pulls]) && !(options[:repo])

    pulls = if !(options[:pulls])
              fetch_pull_requests(options[:repo])
            else
              options[:pulls]
            end
    pulls.select { |pull| pull[:updated_at] < time }
  end

  def pulls_in_range(start_time, end_time, options)
    raise ArgumentError, 'One of :pulls or :repo must be specified in the options hash' if !(options[:pulls]) && !(options[:repo])

    pulls = if !(options[:pulls])
              fetch_pull_requests(options[:repo])
            else
              options[:pulls]
            end
    pulls.select { |pull| (pull[:updated_at] < end_time) && (pull[:updated_at] > start_time) }
  end

  def fetch_tags(repo, options)
    if !(options[:tag_regex])
      '.*'
    else
      options[:tag_regex]
    end

    tags ||= client.tags(repo)

    sort_client_tags tags
  end

  def sort_client_tags(tags)
    pattern = /(\d+\.\d+\.\d+)/

    numeric_tags = tags.select { |t| t.name.match(pattern) }

    numeric_tags.sort_by { |t| Gem::Version.new(t.name.match(pattern)) }.reverse!
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
    raise ArgumentError, 'One of :commits or :time must be specified in the options hash' if !(options[:commits]) && !(options[:time])

    newest_tag = fetch_tags(repo, options).first
    return unless newest_tag

    date_of_tag = date_of_ref(repo, ref_from_tag(newest_tag)).to_dateime
    if options[:time] && (date_of_tag < (DateTime.now - options[:time]))
      puts "#{repo}: A new release is needed" if options[:commits] && (client.commits(repo, since: date_of_tag).count > options[:commits])
    elsif !(options[:time]) && (client.commits(repo, since: date_of_tag).count > options[:commits])
      puts "#{repo}: A new release is needed"
    end
    # else?
  end
  # end

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
    return_val = []
    repo_labels = []
    labels_data = client.labels(repo, {})

    labels_data.each do |label|
      repo_labels.push label.name
    end

    required_labels.each do |required_label|
      return_val.push required_label unless repo_labels.include?(required_label[:name])
    end
    return_val
  end

  def fetch_repo_incorrect_labels(repo, required_labels)
    client.labels(repo, {}).map do |label|
      matching_label = required_labels.find { |l| l[:name] == label.name }
      { name: label.name, color: matching_label[:color] } if matching_label && (matching_label[:color] != label.color)
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
      client.update_label(repo, incorrect_label[:name], color: incorrect_label[:color])
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

  def does_pr_have_label(repo, pr_number, needed_label)
    return_val = false
    labels = client.labels_for_issue(repo, pr_number)
    labels.each do |label|
      return_val = true if label.name == needed_label
    end
    return_val
  end

  def does_pr_merge(repo, pr_number)
    pr = client.pull_request(repo, pr_number, {})
    return_val = pr.mergeable
    return_val
  end
end
