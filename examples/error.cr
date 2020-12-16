require "../src/marmot"

Marmot.repeat(2.seconds) do
  puts "Task running"
  raise "I don't want to live on this planet anymore"
end

puts "Start marmot"
Marmot.run
puts "Marmot is stopped"
