source 'https://rubygems.org'

if RUBY_VERSION <= '2.0.0'
  gem 'octokit', '4.3.0'
else
  gem 'octokit'
end

# gruff appears to have gone dormant. This allows it to install with current
# rmagick, which fixes an imagemagick@6 pkg-config bug.
# https://github.com/topfunky/gruff/pull/186
gem 'gruff', github: "Watson1978/gruff", branch: "rmagick"

group 'development' do
  gem 'pry'
end

