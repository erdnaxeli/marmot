require "random"

require "../src/marmot"

Marmot.every(2.seconds) do |task|
  value = Random.rand(10)
  puts "New value is #{value}"

  if value == 0
    task.cancel
  end
end

puts "Start marmot"
Marmot.run
puts "Marmot is stopped"
