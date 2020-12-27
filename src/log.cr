module Marmot
  Log = ::Log.for(self)
  if level = ENV["MARMOT_DEBUG"]?
    Log.level = ::Log::Severity::Debug
  end
end
