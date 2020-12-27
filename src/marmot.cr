require "log"

require "./log"
require "./tasks"

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
#
# If the computer's clock changes, the tasks scheduled on a specific time will
# *not* be scheduled again.
# Their next runs will be triggered at the time before the clock changes, but the
# next ones will be correctly scheduled.
module Marmot
  VERSION = "0.3.0"

  alias Callback = Proc(Task, Nil)

  @@tasks = Array(Task).new
  @@running = false
  @@stop_channel = Channel(Nil).new

  extend self

  private def add_task(task : Task) : Task
    @@tasks << task
    if @@running
      task.start
    end

    task
  end

  # Runs a task once at a given time.
  def at(time : Time, &block : Callback) : Task
    Log.debug { "New task to run once at #{time}" }
    add_task AtTask.new(time, block)
  end

  # Runs a task every given *span*.
  #
  # If first run is true, it will run as soon as the scheduler runs.
  # Else it will wait *span* time before running for first time.
  def every(span : Time::Span, first_run = false, &block : Callback) : Task
    Log.debug { "New task to repeat every #{span}" }
    add_task RepeatTask.new(span, first_run, block)
  end

  # Runs a task every *span* at the given *day*, *hour*, *minute* and *second*.
  #
  # ```
  # Marmot.every(:hour, hour: 16, minute: 30, second: 30)  # will run every hour at 30:30 (the hour parameter is ignored)
  # Marmot.every(:day, hour: 15) { ... }  # will run every day at 15:00:00
  # Marmot.every(:month, day: 15) { ... } # will run every month at midnight
  # Marmot.every(:month, day: 31) { ... } # will run every month THAT HAVE a 31th day at midnight
  # ```
  def every(span : Symbol, *, day = 1, hour = 0, minute = 0, second = 0, &block : Callback) : Task
    Log.debug { "New task to run every #{span} at #{hour}:#{minute}:#{second}" }
    add_task CronTask.new(span, day, hour, minute, second, block)
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
        remove_canceled_tasks
        next
      end

      if task.is_a?(Task)
        Log.debug { "Running task #{task}" }
        task.run
      end

      remove_canceled_tasks
      if @@tasks.size == 0
        Log.debug { "No remaining task to run, stopping" }
        break
      end
    end

    @@running = false
  end

  # Stops scheduling the tasks.
  def stop
    if @@running
      Log.debug { "Marmot stopped" }
      @@running = false
      @@stop_channel.close
    end
  end

  private def remove_canceled_tasks
    @@tasks.reject! { |task| task.canceled? }
  end
end
