
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