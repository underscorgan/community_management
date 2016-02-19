require 'gruff'
require 'csv'
require 'optparse'

def generate_pr_work_done_graph
  data_set = CSV.read('pr_work_done.csv', headers: true)

  graph = Gruff::Bar.new(800)
  graph.title = 'Supported modules PR work done'

  x_axis = []
  data_set.each { |row|  x_axis << row['week ending on'] }

  count = 0
  data_set.each do |iter|
    graph.labels[count] = iter['week ending on'][5..-1]
    count = count + 1
  end

  graph.label_stagger_height=10

  graph.data("PR's closed", data_set.collect { |x| x['closed'].to_i })
  graph.data("PR's commented", data_set.collect { |x| x['commented'].to_i })
  graph.data("PR's merged", data_set.collect { |x| x['merged'].to_i })

  graph.x_axis_label = 'Week ending'
  graph.y_axis_label = 'PRs'

  graph.write('pr_work_done.png')
end

def prs_created_per_day_graph
  data_set = CSV.read('created_per_day.csv', headers: true)

  graph = Gruff::Bar.new(800)
  graph.title = 'PRs Created Per Day'
  x_axis = []
  data_set.each { |row|  x_axis << row['date'] }

  count = 0
  data_set.each do |iter|
    graph.labels[count] = iter['date'][8..-1]
    count += 1
  end

  graph.label_stagger_height=10

  graph.data("Puppet PRs", data_set.collect { |x| x['puppet'].to_i })
  graph.data("Community PRs", data_set.collect { |x| x['community'].to_i })

  graph.x_axis_label = 'Day (Last 20, ascending)'
  graph.y_axis_label = 'PRs'

  graph.write('prs_created_per_day.png')
end

option_selected = 0
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: graph.rb [options]'
  opts.on('--pr_work_done', 'Generate PR work done') {
    generate_pr_work_done_graph
    option_selected += 1
  }
  opts.on('--created_prs_per_day', 'Generate PRs raised per day') {
    prs_created_per_day_graph
    option_selected += 1
  }
end

parser.parse!

if option_selected == 0
  puts "Missing options, please pick at least one"
  puts parser
  exit
end
