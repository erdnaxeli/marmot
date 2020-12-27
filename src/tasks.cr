require "./log"

module Marmot
  abstract class Task
    Log = Marmot::Log.for(self, Marmot::Log.level)

    @canceled = false
    @callback : Callback = ->(t : Task) {}

    protected getter tick = Channel(Task).new

    # Cancels the task.
    #
    # A canceled task cannot be uncanceled.
    def cancel
      Log.debug { "Task #{self} canceled" }
      @canceled = true
    end

    # Returns true if the task is canceled.
    def canceled?
      @canceled
    end

    protected def run : Nil
      @callback.call(self)
    rescue ex : Exception
      self.cancel
      Log.error(exception: ex) { "An error occurred in task #{self}. The task have been canceled." }
    end

    protected def start : Nil
      spawn do
        while !canceled?
          wait_next_tick

          # The task could have been canceled while we were sleeping.
          if !canceled?
            @tick.send(self)
          end
        end

        @tick.close
      end
    end

    private abstract def wait_next_tick : Nil
  end

  class AtTask < Task
    Log = Task::Log.for(self, Task::Log.level)

    def initialize(@time : Time, @callback : Callback)
    end

    protected def wait_next_tick : Nil
      now = Time.local
      if now < @time
        Log.debug { "Task #{self} sleeping for #{@time - now}" }
        sleep @time - now
      else
        cancel
      end
    end
  end

  class CronTask < Task
    def initialize(@hour : Int32, @minute : Int32, @second : Int32, @callback : Callback)
    end

    protected def wait_next_tick : Nil
      sleep span
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

  class OnChannelTask(T) < Task
    # Gets the value received on the channel.
    #
    # If the channel is closed while waiting, a `nil` value will saved here, and
    # the task will run one last time.
    getter value : T? = nil

    def initialize(@channel : Channel(T), @callback : Callback)
    end

    protected def wait_next_tick : Nil
      if @channel.closed?
        cancel
      else
        @value = @channel.receive?
      end
    end
  end

  class RepeatTask < Task
    Log = Task::Log.for(self, Task::Log.level)

    def initialize(@span : Time::Span, @first_run : Bool, @callback : Callback)
    end

    protected def wait_next_tick : Nil
      if @first_run
        @first_run = false
      else
        Log.debug { "Task #{self} sleeping #{@span}" }
        sleep @span
      end
    end
  end
end
