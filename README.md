# Introducing the lothianbusestimetable gem

    require 'lothianbusestimetable'

    lbt = LothianBusesTimetable.new
    lbt.fetch_timetable '44'
    a = lbt.timetable[:weekday][:outbound]["Meadowbank House"]

    Time.now #=> 2017-08-22 14:06:26 +0100 

    # find the bus times for the 44 (for the next 40 minutes, 20 minutes from now) 
    # from the bus stop near to Meadowbank House heading into town

    a2 = a.select do |x| 
      t = Time.strptime(x, "%H%M")
      (t > Time.now + 60 * 20) and (t < Time.now + 60 * 60)
    end

    #=> ["1432", "1442", "1452", "1502"]

## Resources 

* https://rubygems.org/gems/lothianbusestimetable

timetable bus lothianbuses edinburgh times
