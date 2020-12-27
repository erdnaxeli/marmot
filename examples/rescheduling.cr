require "log"

require "../src/marmot"

# A task that reschedules itself to run twice faster every 10s.
class Task
  @count = 0

  def initialize(@span : Time::Span)
    @now = Time.local
  end

  def run(task) : Nil
    @count += 1

    Log.info { "Run #{@count}" }

    if @span * @count >= 10.seconds
      Log.info { "Rescheduling task" }
      Log.info { "Derivation to goal: #{Time.local - @now - 10.seconds}" }
      task.cancel

      new_task = Task.new(@span / 2)
      Marmot.every(@span / 2) { |t| new_task.run(t) }
    end
  end
end

task = Task.new(10.seconds)
Marmot.every(10.seconds) { |t| task.run(t) }

Log.info { "Start marmot, hit ctrl+c to stop" }
Marmot.run
Log.info { "Marmot is stopped" }
