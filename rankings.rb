require 'sexmachine'
require 'csv'
require 'time'

class Ranking
  def initialize
    @results = {}
  end

  def add_result(percent, race_name) 
    @results[race_name] = percent
  end

  def percent_sum
    values = @results.values.sort.reverse
    max_results = values.length
    if max_results > 4
      max_results = 4
    end

    if (max_results == 0)
      return 0
    end

    sum = 0
    values.take(max_results).each do |value|
      sum += value
    end
    sum
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
        puts "Gender of " + name + " is ambiguous. Assuming male."
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

  def add_event(name, filename)
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
      gender = gender_of_competitor(first_name, last_name)
      if (gender == :male and best_male_time.nil?)
        best_male_time = seconds
        puts "Recorded best male time " + seconds.to_s
      end

      if (gender == :female and best_female_time.nil?)
        best_female_time = seconds
        puts "Recorded best female time " + seconds.to_s
      end

      if (status == '0') then
        #puts name + " " + time
        ranking = ranking_for_competitor(name, gender)
        percent_time = 0
        if (gender == :male)
          percent_time = best_male_time / seconds
        elsif (gender == :female)
          percent_time = best_female_time / seconds
        end

        #puts "Rank of " + name + " is " + (percent_time * 1000).to_s
        ranking.add_result(percent_time, name)
      end
    end 
  end

  def build_rankings(gender)
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
    ranks.each do |rank|
      puts "#" + n.to_s + ": " + rank[:competitor]+ " with " + rank[:ranking].points.to_s
      n += 1
    end
  end
end

ranker = ResultRanker.new
men = ['Jiri Krejci', 'Chris Benn', 'Zbynek Cernin', 'Cameron Devine', 'Gudni Karl', 'Oyvind Naess', 'Chris Bullock', 'Roan McMillan', 'Nevin French']
women = ['Carol Ross', 'Silken Kleer', 'Abra McNair']
ranker.add_gender_exceptions(men, women)
ranker.add_event("SI Race #1: Coal Harbour", "coal_harbour.csv")
puts "Male"
ranker.build_rankings(:male)

puts "Female"
ranker.build_rankings(:female)
