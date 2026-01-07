# the value of `params` is the value of the hash passed to `script_params`
# # in the logstash configuration
def register(params)
end

# the filter method receives an event and must return a list of events.
# Dropping an event means not including it in the return array,
# while creating new ones only requires you to add a new instance of
# LogStash::Event to the returned array
def filter(event)
    doc = event.to_hash
    dc = doc.delete("datacontent")
    dc.each_key { |key|
        event.set(key, dc[key])
    }
    return [event]
end

test "divide event with key datacontent" do
    parameters do
      { "percentage" => 1 }
    end

    in_event { {"name" => "tz","datacontent" => {"a" => 1,"b" => "bbb"} } }

    expect("divide event") do |event|
        event.size == 1
    end
end