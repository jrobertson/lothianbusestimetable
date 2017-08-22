#!/usr/bin/env ruby

# file: lothianbusestimetable.rb

require 'time'
require 'nokorexi'

=begin

# Example usage:

    lbt = LothianBusesTimetable.new
    lbt.fetch_timetable '44'
    lbt.timetable.keys #=> [:service, :weekday, :saturday, :sunday] 
    lbt.timetable[:weekday][:inbound]

    # return the bus times for Juniper Green heading towards Balerno
    lbt.timetable[:weekday][:outbound]["Juniper Green Post Office"]

=end


class LothianBusesTimetable

  attr_reader :timetable

  def initialize
    super()
    @base_url = 'https://lothianbuses.co.uk/timetables-and-maps/timetables/'
  end

  def fetch_timetable(service_number)

    url = @base_url + service_number

    doc = Nokorexi.new(url).to_doc

    table = doc.root.element('//table')

    prev_col = ''
    a0 = []

    # get the destinations
    # inbound and outbound
    table.xpath('tr').each do |tr|

      # get the name
      a = tr.xpath('td//text()').map(&:to_s)

      col1 = a.shift.strip

      if col1 =~ /Service (\w?\d+)/ then

        a0 << {service: $1}

      elsif col1.empty? or col1.length <= 1

        if prev_col.empty? or prev_col.length <= 1 and a0.last.any? then

          a0 << {}

        else

          prev_col = ''
        end

      elsif prev_col =~ /Service \w?\d+/ 

        a0.last.merge!(timetable: col1)    

      else

        if a.any? then

          h = a0.last

          if h.has_key? col1 then
            h[col1].concat a
          else
            h[col1] = a
          end

        else
          a0.pop if a0.last.empty?
        end
      end

      prev_col = col1

    end


    master = {
      service: '',
      weekday: {desc: '', inbound: {}, outbound: {}},
      saturday: {desc: '', inbound: {}, outbound: {}},
      sunday: {desc: '', inbound: {}, outbound: {}}
    }

    h = a0.shift
    master[:service] = h[:service]
    master[:weekday][:desc] = h[:timetable]

    h = a0.shift
    master[:weekday][:inbound] = h
    h = a0.shift
    master[:weekday][:outbound] = h

    h = a0.shift 
    h = a0.shift until h.any?
    master[:saturday][:desc] = h[:timetable]
    h = a0.shift
    master[:saturday][:inbound] = h
    h = a0.shift
    master[:saturday][:outbound] = h

    h = a0.shift 
    h = a0.shift until h.any?
    master[:sunday][:desc] = h[:timetable]
    h = a0.shift
    master[:sunday][:inbound] = h
    h = a0.shift
    master[:sunday][:outbound] = h

    # note: the special character looks like a space 
    #       but is in fact " ".ord #=> 160

    master.to_a[1..-1].each do |key, timetable|

      timetable.to_a[1..-1].each do |direction, printed_rows|

        # find the interval gaps

        a = printed_rows.to_a
        index = a.index a.detect {|x| x.last.grep(/^ $/).any? }
        a2 = a[index].last

        gaps = a2.map.with_index.select {|x,i| x == " "}.map(&:last)

        gaps.delete_at -1 if gaps.last >= a2.length - 1

        # sanitise the times (where short hand times are 
        # given i.e. minutes only)

        printed_rows.each do |name, row|

          prev_time = nil
          printed_rows[name] = row.map.with_index do |col,i|

            if gaps.include? i then
              col
            else
              case col 
              when /^\d{4}$/
                # record the time
                prev_time = Time.strptime(col, "%H%M")
                col
              when /^\d{2}$/

                # substitute with a time
                val = "%02d%02d" % [prev_time.hour, col.to_i]

                #if col is less than minutes, increment the hour
                t = Time.strptime(val, "%H%M")          
                t = t + (60 * 60) if prev_time.min > t.min
                prev_time = t
                t.strftime("%H%M")
              else
                col
              end
            end
          end

        end

        # fill in the gaps

        periods = gaps.map {|i| a.map {|k,v| v[i].to_s.gsub(/\W/,'')}
                    .compact.join(' ').strip }

        gap_times = gaps.zip(periods)


        intervaltimes = gap_times.map do |i, desc|

          interval = desc[/then every (\d+) mins until/,1].to_i

          new_rows = printed_rows.map do |k,v|

            times = []
            next unless v[i-1] && v[i-1] =~ /^\d{4}$/

            t = Time.strptime(v[i-1], "%H%M") #if v[i-1] =~ /^\d{4}$/

            while t + (60 * interval) < Time.strptime(v[i+1], "%H%M") do
              t = t + (60 * interval)
              times << t.strftime("%H%M")
            end

            [k,times]
          end.compact

          [i, new_rows]
        end

        intervaltimes.reverse.each do |i, rows|

          rows.each do |name, xtimes|

            printed_rows[name].delete_at i
            printed_rows[name].insert i, *xtimes    

          end

        end
      end
    end

    @timetable = master

  end
end

