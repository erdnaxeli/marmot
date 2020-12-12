require "./spec_helper"

def expect_channel_eq(channel, value)
  select
  when x = channel.receive
    x.should eq(value)
  else
    fail "#{value} was expected but nothing was received"
  end
end

def expect_channel_be(channel, value)
  select
  when x = channel.receive
    x.should be(value)
  else
    fail "#{value} was expected but nothing was received"
  end
end

def expect_channel_none(channel)
  select
  when x = channel.receive
    fail "No value was expected but #{x} was received"
  else
  end
end

describe Marmot do
  after_each do
    Marmot.stop
    Marmot.cancel_all_tasks
  end

  describe "#repeat" do
    it "schedules a new task that repeats" do
      channel = Channel(Int32).new

      x = 0
      task = Marmot.repeat(20.milliseconds) do
        x += 1
        channel.send(x)
      end
      spawn Marmot.run

      sleep 30.milliseconds
      expect_channel_eq(channel, 1)
      sleep 20.milliseconds
      expect_channel_eq(channel, 2)
      sleep 20.milliseconds
      expect_channel_eq(channel, 3)

      task.cancel
      channel.close
      Marmot.stop
    end

    it "runs on first run if specified" do
      channel = Channel(Int32).new

      x = 0
      task = Marmot.repeat(10.milliseconds, true) do
        x += 1
        channel.send(x)
      end
      spawn Marmot.run

      sleep 5.milliseconds
      expect_channel_eq(channel, 1)

      sleep 1.milliseconds
      expect_channel_none(channel)

      sleep 5.milliseconds
      expect_channel_eq(channel, 2)

      task.cancel
      channel.close
      Marmot.stop
    end
  end

  describe "#cron" do
    it "schedules a new task" do
      channel = Channel(Int32).new

      time = Time.local.at_beginning_of_second + 2.second
      task = Marmot.cron(time.hour, time.minute, time.second) { channel.send(1) }
      spawn Marmot.run

      sleep (time - Time.local + 10.milliseconds)
      expect_channel_eq(channel, 1)

      task.cancel
      channel.close
      Marmot.stop
    end
  end

  describe "#run" do
    it "runs a task without arguments" do
      channel = Channel(Int32).new

      task = Marmot.repeat(3.milliseconds) { channel.send(1) }
      spawn Marmot.run

      sleep 5.milliseconds
      expect_channel_eq(channel, 1)

      task.cancel
      channel.close
      Marmot.stop
    end

    it "runs a task with one argument and gives it its Task object" do
      channel = Channel(Marmot::Task).new

      task = Marmot.repeat(3.milliseconds) { |t| channel.send(t) }
      spawn Marmot.run

      sleep 5.milliseconds
      expect_channel_be(channel, task)

      task.cancel
      channel.close
      Marmot.stop
    end

    it "stops canceled tasks" do
      channel = Channel(Marmot::Task).new

      task = Marmot.repeat(3.milliseconds) do |t|
        t.cancel
        channel.close
      end
      spawn Marmot.run

      sleep 5.milliseconds
      channel.closed?.should be_true
      task.canceled?.should be_true

      Marmot.stop
    end

    it "does not run when there is no tasks" do
      channel = Channel(Int32).new

      task = Marmot.repeat(1.milliseconds) { }
      task.cancel

      spawn do
        Marmot.run
        channel.send(1)
      end

      Fiber.yield
      expect_channel_eq(channel, 1)
      channel.close
    end
  end

  describe "#stop" do
    it "stops the tasks but does not cancel them" do
      channel = Channel(Int32).new

      task = Marmot.repeat(10.milliseconds) { channel.send(1) }
      spawn do
        Marmot.run
        channel.send(2)
      end

      sleep 15.milliseconds
      expect_channel_eq(channel, 1)

      Marmot.stop
      Fiber.yield
      expect_channel_eq(channel, 2)

      task.canceled?.should be_false
    end
  end
end
