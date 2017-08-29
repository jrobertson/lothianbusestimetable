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

    prev_col, prev_bus_stop = '', ''
    a0 = []
    
    tablebreak = 0

    # get the destinations
    # inbound and outbound
    table.xpath('tr').each do |tr|

      # get the name
      tds = tr.xpath('td')#.map(&:unescape)

      a = tds.flat_map {|x| r = x.xpath('.//text()').map(&:unescape); r.any? ? r : ''}

      next unless a.any?

      col1 = a.shift.strip.gsub(',','')
      
      if col1 =~ /^Service (\w?\d+(?:\s*\/\s*\w?\d+)?)/ then

        a0 << {service: $1}
        tablebreak = 0

      elsif prev_col =~ /^Service \w?\d+(?:\s*\/\s*\w?\d+)?/ 
        
        a0.last.merge!(timetable: col1)
        a0 << {}

      elsif col1.empty? and prev_col.empty? and a.length <= 1 
        a0 << {}
        next
      elsif col1.empty? and a.length > 1

        tablebreak += 1 if a0.last and a0.last.any?
        next
      elsif col1.empty? or a.length <= 1
        
        tablebreak += 1 if a0.last and a0.last.any?
        if (prev_col.empty? or prev_col.length <= 1) and a0.last and a0.last.any? then

          if a0.last.keys.first == col1 and prev_col.empty? and a0.last.keys.length > 1 then

            a0 << {} 
          end          

        else

          prev_col = ''
        end

      else

        if a.any? and a.length > 2 and a0.last and col1.length < 40 then

          if a0.last.keys.last == col1 and prev_col.empty? and a0.last.keys.length > 1 then

            a0 << {} 
          end

          next if col1.empty?
          h = a0.last

          tablebreak = 0 if h.empty?
          if h.has_key? col1 then

            if tablebreak == 0 then
              col1 = col1 + ' [R]' 
              h[col1] = a
            else
              h[col1].concat a.take(19)
            end
          else
            h[col1] = a.take(19)
          end


        else

          tablebreak += 1

          next
        end
      end

      prev_col = col1

    end
    #puts 'a0: ' + a0.inspect
        
    master = build_timetable(a0)
    
    #puts 'master: ' + master.inspect

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
  
  def build_timetable(a0)
    
    master = {
      service: '',
      weekday: {desc: '', inbound: {}, outbound: {}},
      saturday: {desc: '', inbound: {}, outbound: {}},
      sunday: {desc: '', inbound: {}, outbound: {}}
    }
        
    h = a0.shift

    master[:service] = h[:service]
    h = a0.shift until h.any? #
    master[:weekday][:desc] = h[:timetable]

    #h = a0.shift
    h = a0.shift until h.any? and not h[:service]

    master[:weekday][:inbound] = h
    h = a0.shift
    a0.reject! {|x| x.empty?}

    
    if a0.first and a0.first.any? then
      
      #h = a0.shift
      h = a0.shift until h.any?

      master[:weekday][:outbound] = h unless h.has_key? :timetable

      h = a0.shift unless h.has_key? :timetable

      
      if h and a0.any? and h[:timetable] != 'Public Holiday Timetable' then
        
        h = a0.shift until h.any?

        master[:saturday][:desc] = h[:timetable]
        h = a0.shift until h.any? and not h[:service]
        master[:saturday][:inbound] = h
        h = a0.shift

        return master unless a0.any?
        h = a0.shift until h.any?

        master[:saturday][:outbound] = h unless h.has_key? :timetable

        
        h = a0.shift until h.any?   

        if h and a0.any? then
          h = a0.shift
          h = a0.shift until h.any?
          master[:sunday][:desc] = h[:timetable]
          h = a0.shift
          h = a0.shift until h.any?

          master[:sunday][:inbound] = h
          h = a0.shift until h.any?
          master[:sunday][:outbound] = h
          
        end
      end
    end    
    
    return master
  end
  
  def every_hourlyset_interval(rows, i)    
    
    rows.map do |k,v|
      
      # some limited bus stops don't apply
      next unless v.detect {|x| x =~ /^\d{2} *$/}
      
      # the next statement caters for special journey entries which happen at 
      # limited times of the day
      
      i -= 19 if v.length < i 
      
      start_i = i - 1

      start_i -= 1 while v[start_i] =~ /^(?:\d{2}|-|\||[A-Z]|) *$/

      times = []

      a = v[start_i+1..i-1].cycle

      # get the starting hour

      t1 = Time.strptime(v[start_i], "%H%M")

      prev_time = t1

      t2 = t1

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
    # todo 26-Aug-2017
    # here we will add 
    return unless interval
    
    rows.map do |k,v|
      
      next unless v.is_a? Array

      times = []
      
      next unless v[i-1]
      
      if v[i-1] =~ /^\d{2} *$/ then
        
        j = i - 1
        j -= 1 until v[j] =~ /^\d{4}/

        t0 = Time.strptime(v[j], "%H%M")
        prev_time = t0
        
        (j+1..i-1).each do |k| 
          
          s = "%02d%s" % [t0.hour, v[k]]
          new_time = Time.strptime(s, "%H%M")
          new_time += (60 * 60) if new_time < prev_time
          prev_time = new_time

          #times << new_time.strftime("%H%M")
          v[k] = new_time.strftime("%H%M")

        end
      end

      next unless v[i-1] =~ /^\d{4} *$/
      t = Time.strptime(v[i-1], "%H%M") #if v[i-1] =~ /^\d{4}$/

      while t + (60 * interval.to_i) < Time.strptime(v[i+1], "%H%M") do
        t = t + (60 * interval.to_i)
        times << t.strftime("%H%M")
      end

      [k, times ]
    end.compact    
  end
  
  alias every_hourly_interval every_interval
  
end