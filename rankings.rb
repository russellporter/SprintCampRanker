#!/usr/bin/env ruby

# How to use
# 1. Download this script and save it in its own folder
# 2. Install ruby 1.9.3. This works on Windows: http://rubyinstaller.org/downloads/
# 3. Open a command prompt with Ruby 
#    (if using the Windows RubyInstaller, search your Windows 
#     applications for "Start Command Prompt with Ruby")
# 4. Install sexmachine (for distinguishing genders): gem install sexmachine
# 5. "cd" to the folder where this script is saved
# 6. Edit the rankings.rb config so it uses your event config CSV
# 7. Run the script: ruby rankings.rb
# 8. Based on the output, specify people with ambiguous gender in the config

require 'sexmachine'
require 'csv'
require 'time'

class Ranking
  attr_reader :results
  attr_reader :time_results

  def initialize
    @results = {}
    @time_results = {}
  end

  def add_result(percent, race_name, time) 
    @results[race_name] = percent
    @time_results[race_name] = time
  end

  def percent_sum
    sum = 0
    included_events.each do |item|
      sum += item[:result]
    end
    sum
  end

  def included_events
    results_a = []
    @results.each { |event, result|
      results_a << { :event => event, :result => result }
    }
    results_a = results_a.sort_by { |item| item[:result] }.reverse
    max_results = results_a.length
    if max_results > MAX_COUNTED_EVENTS
      max_results = MAX_COUNTED_EVENTS
    end

    if (max_results == 0)
      return 0
    end

    results_a.take(max_results)
  end

  def points
    percent_sum * 1000
  end
end

class ResultRanker
  # name: ranking

  def initialize
    @male_competitors = {}
    @female_competitors = {}
    @known_men = []
    @known_women = []
    @races = []
    @detector = SexMachine::Detector.new
  end

  def ranking_for_male_competitor(name)
    if (!(@male_competitors.has_key? name))
      @male_competitors[name] = Ranking.new
    end

    @male_competitors[name]
  end

  def ranking_for_female_competitor(name)
    if (!(@female_competitors.has_key? name))
      @female_competitors[name] = Ranking.new
    end

    @female_competitors[name]
  end

  def gender_of_competitor(first_name, last_name)
    name = first_name + " " + last_name
    gender = nil
    if (@known_men.include? name)
      gender = :male
    elsif (@known_women.include? name)
      gender = :female
    else
      gender = @detector.get_gender(first_name)
      if (!([:male, :female].include? gender))
        puts "ERROR: Gender of " + name + " is ambiguous. Assuming male."
        gender = :male
      end
    end

    gender
  end

  def ranking_for_competitor(name, gender)
    if (gender == :male)
      ranking_for_male_competitor(name)
    else
      ranking_for_female_competitor(name)
    end
  end

  def add_gender_exceptions(men, women)
    @known_men = men
    @known_women = women
  end

  def add_event(event_name, filename, valid_klass)
    @races << event_name
    options = { :headers => true, :col_sep => ';', :encoding => Encoding.find("ISO-8859-1") }
    best_male_time = nil
    best_female_time = nil
    CSV.foreach(filename, options) do |row|
      last_name = row[3]
      first_name = row[4]
      name = first_name + " " + last_name
      time = row[11]
      seconds = 0
      if (!row[10].nil? && !row[9].nil?)
        seconds = Time.parse(row[10]) - Time.parse(row[9])
        #puts "Parse time " + seconds.to_s + ", " + name
      end
      status = row[12]
      klass = row[17]
      gender = gender_of_competitor(first_name, last_name)

      if (status == '0' and klass == valid_klass) then
        if (gender == :male and best_male_time.nil?)
          best_male_time = seconds
          puts "Recorded best male time " + seconds.to_s
        end

        if (gender == :female and best_female_time.nil?)
          best_female_time = seconds
          puts "Recorded best female time " + seconds.to_s
        end

        ranking = ranking_for_competitor(name, gender)
        percent_time = 0
        if (gender == :male)
          percent_time = best_male_time / seconds
        elsif (gender == :female)
          percent_time = best_female_time / seconds
        end

        #puts "Rank of " + name + " is " + (percent_time * 1000).to_s
        minutes_t = (seconds / 60).floor
        seconds_t = (seconds % 60).round.to_s
        ranking.add_result(percent_time, event_name, minutes_t.to_s + ":" + "%02d" % seconds_t)
      elsif (status == '0')
        ranking = ranking_for_competitor(name, gender)
        ranking.add_result(0, event_name, "Short")
      end
    end 
  end

  def build_rankings(gender, f)
    competitors = nil
    if (gender == :male)
      competitors = @male_competitors
    elsif (gender == :female)
      competitors = @female_competitors
    end

    ranks = []
    competitors.each do |competitor, ranking|
      ranks << { :competitor => competitor, :ranking => ranking }
    end

    ranks.sort! do |a, b|
      b[:ranking].points <=> a[:ranking].points
    end

    n = 1
    f.puts '<table class="table table-striped">'
    f.puts '<thead>'
    f.puts '<tr>'
    f.puts '<th>#</th>'
    f.puts '<th>Name</th>'
    f.puts '<th>Points</th>'
    @races.each do |race|
      f.puts '<th>' + race + '</th>'
    end
    f.puts '</tr>'
    f.puts '</thead>'
    f.puts '<tbody>'
    ranks.each do |rank|
      ranking = rank[:ranking]
      f.puts '<tr>'
      f.puts '<td>' + n.to_s + '</td>'
      f.puts '<td>' + rank[:competitor] + "</td>"
      f.puts '<td>' + '%.2f' % ranking.points + '</td>'
      @races.each do |race|
        f.puts '<td>'
        results = ranking.results
        included_events = ranking.included_events
        excluded = true
        included_events.each { |event|
          if (event[:event] == race) then
            excluded = false
          end
        }
        if excluded then
          f.puts '<del>'
        end
        if results.has_key? race
          f.puts '%.2f' % (results[race] * 1000) + " (" + ranking.time_results[race] + ")"
        end
        if excluded then
          f.puts '</del>'
        end
        f.puts '</td>'
      end
      f.puts '</tr>'
      n += 1
    end
    f.puts '</tbody>'
    f.puts '</table>'
  end
end

# CONFIGURATION
# This is the number of event results we include in the results
# If someone goes to more than this many events at sprint camp, we pick their top n results
MAX_COUNTED_EVENTS = 4

ranker = ResultRanker.new

# If you get errors about ambiguous gender, specify the person's name here in the correct category
# Also, if the auto-gender detection is incorrect, you can override by adding the person's name here
men = ['Jiri Krejci', 'Chris Benn', 'Zbynek Cernin', 'Cameron Devine', 'Gudni Karl', 'Oyvind Naess', 'Chris Bullock', 'Roan McMillan', 'Nevin French']
women = ['Carol Ross', 'Silken Kleer', 'Abra McNair']
ranker.add_gender_exceptions(men, women)
# Add each event at sprint camp
# The number "1" is the klass number of the participants we want to rank
# For example, at sprint camp 2014, there were long and short classes
# Look in your CSV file or in MeOS to determine the klass number of the event you want to rank.
ranker.add_event("#1: Coal Harbour", "coal harbour.csv", '1')
ranker.add_event("#2: Mundy Park", "Mundy Park.csv", '1')
ranker.add_event("#3: Hume Park Farsta", "farsta.csv", '118')

email = "support@whyjustrun.ca"

# This outputs the HTML file
File.open('sprint_camp_rankings.html', 'w') do |file|
  file.puts '<html><head>'
  file.puts '<link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.1.0/css/bootstrap.min.css">'
  file.puts '</head><body><div class="container">'
  file.puts '<header class="page-header">'
  file.puts "<h1>Sprint Camp " + Time.now.year.to_s + " Rankings</h1>"
  file.puts '</header>'
  file.puts '<p class="bg-warning" style="padding: 15px; max-width: 450px">'
  file.puts '<span class="glyphicon glyphicon-question-sign"></span> See a problem? Email <a href="' + email + '">' + email + '</a>'
  file.puts '</p>'
  file.puts '<h2>Men</h2>'
  ranker.build_rankings(:male, file)
  file.puts '<h2>Women</h2>'
  ranker.build_rankings(:female, file)
  file.puts '</div></body></html>'
end
