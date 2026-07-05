# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

# The sync tasks and `sync:list` derive from the registered fetcher classes, so
# the app is loaded here to enumerate them.
$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "needham_circle"

namespace :sync do
  def run_sync(fetcher)
    require "logger"

    logger = Logger.new($stdout)
    secrets = NeedhamCircle::Env.secrets
    sync =
      NeedhamCircle::Sync::Runner.new(
        calendar: NeedhamCircle::GoogleCalendar.new(secrets.fetch("SERVICE_ACCOUNT_KEY")),
        calendar_id: secrets.fetch("EVENTS_CALENDAR_ID"),
        fetcher: fetcher.new(logger: logger),
        logger: logger
      )

    exit(sync.call ? 0 : 1)
  end

  NeedhamCircle::Sync.fetchers.each do |fetcher|
    name = NeedhamCircle::Sync.name_for(fetcher)
    desc "Sync #{name} events into the public Google Calendar"
    task(name.to_sym) { run_sync(fetcher) }
  end

  desc "Print the sync source names as a JSON array (drives the CI matrix)"
  task(:list) do
    require "json"
    puts JSON.generate(NeedhamCircle::Sync.source_names)
  end
end
