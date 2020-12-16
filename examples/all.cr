require "log"
require "random"

require "../src/marmot"

Marmot.repeat(3.seconds) do |task|
  value = Random.rand(10)
  if value == 0
    Log.info { "New value is #{value}, cancelling myself" }
    task.cancel
  else
    Log.info { "New value is #{value}, not cancelling yet" }
  end
end

channel_ping = Channel(String).new(1)
channel_pong = Channel(String).new

Marmot.on(channel_ping) do |task|
  Log.info { task.as(Marmot::OnChannelTask).value }

  spawn do
    sleep Random.rand(8).second
    channel_pong.send("pong")
  end
end

Marmot.on(channel_pong) do |task|
  Log.info { task.as(Marmot::OnChannelTask).value }

  spawn do
    sleep Random.rand(8).second
    channel_ping.send("ping")
  end
end

Marmot.repeat(1.5.seconds) do
  if Random.rand(10) == 0
    raise "I don't want to live on this planet anymore"
  else
    Log.info { "No error yet" }
  end
end

Marmot.repeat(5.second) { Log.info { "Hi" } }
Marmot.cron(hour: 4, minute: 25) { puts "It is 4:25 pm" }

channel_ping.send("ping")

puts "Start marmot, hit ctrl+c to stop."
Marmot.run
puts "Marmot is stopped"
