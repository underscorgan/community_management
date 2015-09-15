Community Management
====================

Utilities using octokit to help with managing community repositories and PR Triage.

Github Setup
--------------

For authentication, follow the steps here to get your OAth token generated: https://help.github.com/articles/creating-an-access-token-for-command-line-use . The default scope options are fine.
You can set your Github OAuth token in the `GITHUB_COMMUNITY_TOKEN` environment variable instead of using the `-t` option.

Initial Setup
--------------

Install required libraries: eg
'bundle install --path .bundle/gems/'

An Example Run
---------------

An example for running stats on all supported puppetlabs modules:
'bundle exec ruby stats.rb -n puppetlabs --puppetlabs-supported -t (ACCESS TOKEN HERE) -o -w'

Pull Requests
--------------

Display pull requests on modules in a github organisation, filtered by various
criteria. Use the `--help` flag to see all parameters.

Release Planning
-----------------

Show modules that should receive a release "soon". Use the `--help` flag to see
all parameters.

Stats
------

Retrieve modules stats and publishes a report. Use the `--help` flag to see all parameters.
To view the report:
'open report.html'

Labels
-------

Puts a set of labels into each repository. Creates them in a non destructive way.

Npc
----

Updates the modules with comments and labels pull requests that require rebase.
