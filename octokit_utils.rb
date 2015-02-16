#!/usr/bin/env ruby

require 'octokit'

class OctokitUtils
  attr_accessor :client

  def initialize(access_token)
    Octokit.auto_paginate = true
    @client = Octokit::Client.new(:access_token => "#{access_token}")
    user = client.user
    user.login
  end

  def list_repos(organization, repo_regex='.*')
    repos ||= client.organization_repositories(organization).collect {|org| org[:name] if org[:name] =~ /#{repo_regex}/}
    # The collection leaves nil entries in for non-matches
    repos = repos.select {|repo| repo }
    return repos.sort.uniq
  end

  def fetch_pull_requests(repo, options={:state=>'open', :sort=>'updated'})
    prs ||= client.pulls(repo, options)
    prs
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

  def fetch_tags(repo, tag_regex='.*')
    tags ||= client.tags(repo)
    tags.select {|tag| tag[:name] =~ /#{tag_regex}/}
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
end
