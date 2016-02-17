require 'gruff'
require 'csv'

google = CSV.read('work_done.csv', headers: true)

graph = Gruff::Bar.new(1024)
graph.title = 'Supported module PR work done'

x_axis = []
google.each { |row|  x_axis << row['week ending on'] }

count = 0
google.each do |iter|
  graph.labels[count] = iter['week ending on'][5..-1]
  count = count + 1
end

graph.label_stagger_height=10

graph.data('closed', google.collect { |x| x['closed'].to_i })
graph.data('commented', google.collect { |x| x['commented'].to_i })
graph.data('merged', google.collect { |x| x['merged'].to_i })

graph.x_axis_label = 'Week ending'
graph.y_axis_label = 'PRs'

graph.write('google_stock.png')
