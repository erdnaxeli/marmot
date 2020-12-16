require "../src/marmot"

channel_ping = Channel(String).new(1)
channel_pong = Channel(String).new

Marmot.on(channel_ping) do |task|
  puts task.as(Marmot::OnChannelTask).value

  # We want to avoid blocking tasks, so we sleep in another fiber
  spawn do
    sleep 1.second
    channel_pong.send("pong")
  end
end

Marmot.on(channel_pong) do |task|
  puts task.as(Marmot::OnChannelTask).value

  spawn do
    sleep 1.second
    channel_ping.send("ping")
  end
end

channel_ping.send("ping")

puts "Start marmot, hit ctrl+c to stop."
Marmot.run
puts "Marmot is stopped"
