# Marmot is a scheduler, use it to schedule tasks.
module Marmot
  VERSION = "0.1.0"

  alias Callback = Proc(Task, Nil)

  @@tasks = Array(Task).new
  @@stopped = true
  @@stop_channel = Channel(Nil).new

  abstract class Task
    @canceled = false
    @callback : Callback = ->(t : Task) {}

    getter tick = Channel(Task).new

    # :nodoc:
    abstract def start : Nil

    # Cancels the task.
    #
    # A canceled task cannot be uncanceled.
    def cancel
      @canceled = true
    end

    # Returns true if the task is canceled.
    def canceled?
      @canceled
    end

    # :nodoc:
    def run : Nil
      @callback.call(self)
    rescue
    end
  end

  class Repeat < Task
    def initialize(@span : Time::Span, @first_run : Bool, @callback : Callback)
    end

    def start : Nil
      spawn do
        while !canceled?
          if @first_run
            @first_rune = false
          else
            sleep @span
          end

          # The task could have been canceled while we were sleeping.
          if !canceled?
            @tick.send(self)
          end
        end

        @tick.close
      end
    end
  end

  class Cron < Task
    def initialize(@hour : Int32, @minute : Int32, @second : Int32, @callback : Callback)
    end

    def start : Nil
      spawn do
        while !@canceled
          sleep span
          @tick.send(self)
        end
      end
    end

    private def span
      # We want the next minute, we skip the current one.
      time = Time.local.at_beginning_of_second + 1.second

      if time.second < @second
        time += (@second - time.second).second
      elsif time.second > @second
        time += (60 - time.second + @second).second
      end

      if time.minute < @minute
        time += (@minute - time.minute).minute
      elsif time.minute > @minute
        time += (60 - time.minute + @minute).minute
      end

      if time.hour < @hour
        time += (@hour - time.hour).hour
      elsif time.hour > @hour
        time += (24 - time.hour + @hour).hour
      end

      time - Time.local
    end
  end

  extend self

  # Runs a task every given *span*.
  #
  # If first run is true, it will run as soon as the scheduler runs.
  # Else it will wait *span* time, then run a first time.
  def repeat(span : Time::Span, first_run = false, &block : Callback) : Task
    task = Repeat.new(span, first_run, block)
    @@tasks << task
    task
  end

  # Runs a task every day at *hour* and *minute*.
  def cron(hour, minute, second = 0, &block : Callback) : Task
    task = Cron.new(hour, minute, second, block)
    @@tasks << task
    task
  end

  # Starts scheduling the tasks.
  #
  # This blocks until `#stop` is called.
  def run : Nil
    @@stopped = false
    @@stop_channel = Channel(Nil).new
    remove_canceled_tasks

    if @@tasks.size == 0
      return
    end

    @@tasks.map(&.start)

    while !@@stopped
      begin
        m = Channel.receive_first([@@stop_channel] + @@tasks.map(&.tick))
      rescue Channel::ClosedError
        break
      end

      if m.is_a?(Task)
        m.run
      end
      remove_canceled_tasks
    end
  end

  # Stops scheduling the tasks.
  def stop
    if !@@stopped
      @@stopped = true
      @@stop_channel.close
    end
  end

  private def remove_canceled_tasks
    @@tasks.reject! { |task| task.canceled? }
  end
end
