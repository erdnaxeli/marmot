# marmot

Marmot is a scheduler, use it to schedule tasks.

The most detailled documentation is [the api doc](https://erdnaxeli.github.io/marmot/Marmot.html).

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     marmot:
       github: erdnaxeli/marmot
   ```

2. Run `shards install`

## Usage

```crystal
require "marmot"

repetitions

# This task will repeat every 15 minutes.
repeat_task = Marmot.repeat(15.minutes) { puts Time.local }
# This task will run every day at 15:28:43, and will cancel the previous task.
Marmot.cron(hour: 15, minute: 28, second: 43) do
  puts "It is 15:28:43: #{Time.local}"
  repeat_task.cancel
end

times = 0
# This task will run every 10 seconds and will cancel itself after 10 runs.
Marmot.repeat(10.seconds) do |task|
  times += 1
  puts "#{times} times"
  task.cancel if times = 10
end

# Start the scheduler.
Marmot.run
```

### Debug

You can set the env var `MARMOT_DEBUG` to any value to make marmot outputs debug logs.

## Development

Don't forget to run the test.

As they deal with timing, they could fail if your computer is busy.
Do not hesitate to run then many times if that happens.

## Contributing

1. Fork it (<https://github.com/erdnaxeli/marmot/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [erdnaxeli](https://github.com/erdnaxeli) - creator and maintainer
