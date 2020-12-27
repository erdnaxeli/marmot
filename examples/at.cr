require "log"

require "../src/marmot"

time = Time.local + 10.seconds

Log.info { "Scheduling a task to run at #{time}" }
Marmot.at(time) { Log.info { "Running at #{time}" } }

Log.info { "Start marmot" }
Marmot.run
Log.info { "Marmot is stopped" }
