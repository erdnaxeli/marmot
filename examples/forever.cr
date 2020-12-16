require "../src/marmot"

Marmot.repeat(1.second) { puts "Hi" }
Marmot.cron(hour: 4, minute: 25) { puts "It is 4:25 pm" }

puts "Start marmot. hit ctrl+c to stop."
Marmot.run
puts "Marmot is stopped"
