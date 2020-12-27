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
    def initialize(@span : Symbol, @day : Int32, @hour : Int32, @minute : Int32, @second : Int32, @callback : Callback)
      if !{:minute, :hour, :day, :month}.includes?(@span)
        raise "Unknown span #{@span}"
      end
    end

    protected def wait_next_tick : Nil
      sleep span
    end

    private def span
      # We want the next minute, we skip the current one.
      time = Time.local.at_beginning_of_second + 1.second

      time = adjust_second(time)
      if @span == :minute
        return time - Time.local
      end

      time = adjust_minute(time)
      if @span == :hour
        return time - Time.local
      end

      time = adjust_hour(time)
      if @span == :day
        return time - Time.local
      end

      time = adjust_day(time)
      time - Time.local
    end

    private def adjust_second(time)
      if time.second < @second
        time + (@second - time.second).second
      elsif time.second > @second
        time + (60 - time.second + @second).second
      else
        time
      end
    end

    private def adjust_minute(time)
      if time.minute < @minute
        time + (@minute - time.minute).minute
      elsif time.minute > @minute
        time + (60 - time.minute + @minute).minute
      else
        time
      end
    end

    private def adjust_hour(time)
      if time.hour < @hour
        time + (@hour - time.hour).hour
      elsif time.hour > @hour
        time + (24 - time.hour + @hour).hour
      else
        time
      end
    end

    private def adjust_day(time)
      if time.day < @day
        time + (@day - time.day).day
      elsif time.day > @day
        while time.day != @day
          time += 1.day
        end
        time
      else
        time
      end
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
