require "log"

# Marmot is a non concurrent scheduler.
#
# Marmot schedules tasks on three possibles ways:
# * on a periodic span (`Marmot.repeat`)
# * every day at a given time (`Marmot.cron`)
# * when a value is available on a channel (`Marmot.on`)
#
# Tasks are all executed on the same fiber.
# This means two things: first, you don't have to worry about concurrency
# (your tasks can share objects which does not support concurrency, like
# `HTTP::Client`), and second, they must not block (too much).
# If you want to execute jobs concurrently, you must spawn a new fiber inside your
# tasks.
#
# A task receive a unique parameter which is an object representing itself.
# It can be canceled with `Marmot::Task#cancel`, from inside or outside the task.
# A canceled task can never be started again.
#
# Tasks do not start when created.
# Instead, the main entrypoint is `Marmot.run`, which blocks while there are tasks
# to run. If there is no tasks to run, or they are all canceled, it stops.
#
# The blocking behavior can also be stopped by calling `Marmot.stop`.
# As `Marmot.run` is blocking, you probably want to call `Marmot.stop` from a task
# or from another fiber.
#
# When stopped, the tasks are not canceled and they will run again if `Marmot.run`
# is called again.
# To cancel all the tasks there is `Marmot.cancel_all_tasks`.
module Marmot
  VERSION = "0.2.1"

  alias Callback = Proc(Task, Nil)

  Log = ::Log.for(self)
  if level = ENV["MARMOT_DEBUG"]?
    Log.level = ::Log::Severity::Debug
  end

  @@tasks = Array(Task).new
  @@running = false
  @@stop_channel = Channel(Nil).new

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

  extend self

  private def add_task(task : Task) : Task
    @@tasks << task
    task
  end

  # Runs a task every day at *hour* and *minute*.
  def cron(hour, minute, second = 0, &block : Callback) : Task
    Log.debug { "New task to run every day at #{hour}:#{minute}:#{second}" }
    add_task CronTask.new(hour, minute, second, block)
  end

  # Runs a task when a value is received on a channel.
  #
  # To access the value, you need to restrict the type of the task, and use
  # `OnChannelTask#value`.
  #
  # ```
  # channel = Channel(Int32).new
  # Marmot.on(channel) { |task| puts task.as(OnChannelTask).value }
  # ```
  def on(channel, &block : Callback) : Task
    Log.debug { "New task to run on message on #{channel}" }
    add_task OnChannelTask.new(channel, block)
  end

  # Runs a task every given *span*.
  #
  # If first run is true, it will run as soon as the scheduler runs.
  # Else it will wait *span* time before running for first time.
  def repeat(span : Time::Span, first_run = false, &block : Callback) : Task
    Log.debug { "New task to repeat every #{span}" }
    add_task RepeatTask.new(span, first_run, block)
  end

  # Cancels all the tasks.
  def cancel_all_tasks : Nil
    @@tasks.each { |t| t.cancel }
  end

  # Starts scheduling the tasks.
  #
  # This blocks until `#stop` is called or all tasks are cancelled.
  def run : Nil
    Log.debug { "Marmot running" }

    @@running = true
    @@stop_channel = Channel(Nil).new
    remove_canceled_tasks

    if @@tasks.size == 0
      Log.debug { "No task to run! Stopping." }
      return
    end

    @@tasks.map(&.start)

    while @@running
      Log.debug { "Waiting for a task to run among #{@@tasks.size} tasks" }
      begin
        task = Channel.receive_first([@@stop_channel] + @@tasks.map(&.tick))
      rescue Channel::ClosedError
        Log.debug { "Marmot stopped" }
        break
      end

      if task.is_a?(Task)
        Log.debug { "Running task #{task}" }
        task.run
      end

      remove_canceled_tasks
      if @@tasks.size == 0
        break
      end
    end
  end

  # Stops scheduling the tasks.
  def stop
    if @@running
      @@running = false
      @@stop_channel.close
    end
  end

  private def remove_canceled_tasks
    @@tasks.reject! { |task| task.canceled? }
  end
end
