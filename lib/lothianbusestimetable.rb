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
      a = tr.xpath('td//text()').map(&:unescape)

      next unless a.any?

      col1 = a.shift.strip

      if col1 =~ /^Service (\w?\d+)/ and a0.empty?then

        a0 << {service: $1}

      elsif prev_col =~ /^Service \w?\d+$/ 

        a0.last.merge!(timetable: col1)
        a0 << {}
#=begin       
      elsif col1.empty? and a.length > 1
        next
      elsif col1.empty? or a.length <= 1
        
        #next if a.length < 1
        if prev_col.empty? or prev_col.length <= 1 and a0.last and a0.last.any? then

          a0 << {}

        else

          prev_col = ''
        end
#=end        
      else

        if a.any? and a.length > 1 then

          next if col1.empty?
          h = a0.last
          
          if h.has_key? col1 then
            h[col1].concat a
          else
            h[col1] = a
          end

        else

          #a0.pop if a0.last.empty?
          next
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
    
    if h and a0.any? then
      
      h = a0.shift until h.any?
      master[:sunday][:desc] = h[:timetable]
      h = a0.shift
      master[:sunday][:inbound] = h
      h = a0.shift
      master[:sunday][:outbound] = h
      
    end


    master.to_a[1..-1].each do |key, timetable|

      timetable.to_a[1..-1].each do |direction, printed_rows|

        next unless printed_rows

        # find the interval gaps

        a = printed_rows.to_a

        index = a.index a.detect {|x| x.last.grep(/^then$/).any? }

        if index then
          a2 = a[index].last

          gaps = a2.map.with_index.select {|x,i|  x == 'then'}.map(&:last)

          gaps.delete_at -1 if gaps.last >= a2.length - 1
        else
          gaps = []
        end

        
        # sanitise the times (where short hand times are 
        # given i.e. minutes only)

=begin
# sanitise diabled for now
# probably perform this at the end now

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

                next if prev_time.nil?
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
=end
        # fill in the gaps

        periods = gaps.map {|i| a.map {|k,v| v[i].to_s.gsub(/\W/,' ')}
                    .compact.join(' ').strip }

        gap_times = gaps.zip(periods)


        intervaltimes = gap_times.map do |i, desc|
          
          intervals = []

          if desc =~ /^then every hour(?: until)?/ then
            new_rows = every_hourly_interval printed_rows, i
          elsif desc =~ /^then at these mins past each hour(?: until)?/                        

            new_rows = every_hourlyset_interval printed_rows, i
          else
            interval = desc[/then (?:at least )?every (\d+) mins(?: until)?/,1]
            new_rows = every_interval printed_rows, i, interval
          end

          [i, new_rows]
        end

        intervaltimes.reverse.each do |i, rows|
          
          rows.each do |name, xtimes, del_indices|

            printed_rows[name].delete_at i
            printed_rows[name].insert i, *xtimes    
            del_indices.to_a.reverse.each {|j| printed_rows[name].delete_at j}

          end

        end
      end
    end

    @timetable = master

  end
  
  def services()
    
    return @services if @services
    
    url = @base_url + '1'

    doc = Nokorexi.new(url).to_doc

    o = doc.root.xpath('//optgroup').map do |options|
      
      [
        options.attributes[:label].sub(' services',''),  
        options.xpath('option/text()').map do |x| 
          %i(number name).zip(x.to_s.split(/ - /,2)).to_h
        end
      ]

    end

    @services = o.to_h
      
  end
  
  private
  
  def every_hourlyset_interval(rows, i)    
    
    rows.map do |k,v|

      i -= 19 if v.length < i # caters for special journey entries which happen at limited times of the day
      start_i = i - 1

      start_i -= 1 while v[start_i] =~ /^(?:\d{2}|-|\||[A-Z]|) *$/

      times = []

      a = v[start_i+1..i-1].cycle

      # get the starting hour

      t1 = Time.strptime(v[start_i], "%H%M")

      prev_time = t1

      t2 = t1
      #j = v[i+1] =~ /^\d{4}/ ? i+1 : i+2      
      j = i + 1
      j += 1 until v[j] =~ /^\d{4}/

      t3 = Time.strptime(v[j].rstrip, "%H%M")

      while t2 < t3  do

        val = a.next

        if val =~ /^\d{2} *$/ then

          t2 = Time.strptime("%02d%s" % [prev_time.hour, val], "%H%M")

          t2 += 60 * 60 if t2 <= prev_time

          times << t2.strftime("%H%M") if t2 < t3
          prev_time = t2
        else
          times << val
        end

      end    
      [k,times, (start_i+1..i-1)]
    end.compact    
    

  end  

  def every_interval(rows, i, interval=60)
    
    return unless interval
    
    rows.map do |k,v|

      times = []
      
      next unless v[i-1] && v[i-1] =~ /^\d{4}$/

      t = Time.strptime(v[i-1], "%H%M") #if v[i-1] =~ /^\d{4}$/

      while t + (60 * interval.to_i) < Time.strptime(v[i+1], "%H%M") do
        t = t + (60 * interval.to_i)
        times << t.strftime("%H%M")
      end

      [k,times]
    end.compact    
  end
  
  alias every_hourly_interval every_interval
  
end