# frozen_string_literal: true

require_relative "game_log_analyze/version"
require "thor"
require "rainbow"
require "time"
require "debug"

STAR_WARS_GALAXIES_REGEX = /^\[Combat\]\s+(\d{2}:\d{2}:\d{2})\s+.*\s(\d+)\spoints of damage.*$/.freeze

#
# Entry point for the GameLogAnalyze module
#
module GameLogAnalyze
  def self.total_damage(damage_time_points)
    damage_time_points.map { |x| x[1] }.inject(:+)
  end

  def self.damage_per_second(damage_time_points, end_time = Time.now)
    return 0 if damage_time_points.empty?

    total_damage = total_damage(damage_time_points)
    if damage_time_points.empty?
      0
    else
      total_time = end_time - damage_time_points.first[0]
      total_damage.to_f / total_time
    end
  end

  def self.average_hit(damage_time_points)
    return 0 if damage_time_points.empty?

    total_damage = total_damage(damage_time_points)
    total_damage.to_f / damage_time_points.size
  end

  def self.damage_data_point_from_line(line)
    matched = line.match(STAR_WARS_GALAXIES_REGEX)
    return nil unless matched

    time = Time.parse(matched.captures[0])
    damage = matched.captures[1].to_i
    [time, damage]
  end

  def self.trim_data_point(data_points, duration_seconds, end_time = Time.now)
    return false if data_points.empty?
    return false if data_points.first[0] > (end_time - duration_seconds)

    data_points.shift
    true
  end

  def self.print_data_points(data_points)
    dps = GameLogAnalyze.damage_per_second(data_points)
    total = GameLogAnalyze.total_damage(data_points)
    average_hit = GameLogAnalyze.average_hit(data_points)

    print "\e[H\e[2J"

    dps_label = Rainbow("DPS:").blue.bright.underline
    dps_value = Rainbow(dps).green.bright

    total_label = Rainbow("Total:").blue.bright.underline
    total_value = Rainbow("#{total} over #{data_points.size} samples").green.bright

    average_hit_label = Rainbow("Average Hit:").blue.bright.underline
    average_hit_value = Rainbow(average_hit).green.bright

    puts Rainbow("Game Log Analyzer").red.bright.underline
    puts "-----------------------"
    puts "#{dps_label} #{dps_value}"
    puts "#{total_label} #{total_value}"
    puts "#{average_hit_label} #{average_hit_value}"
  end

  class Error < StandardError; end

  class CLI < Thor
    desc "track FILE_NAME", "track stats for the log at FILE_NAME"
    def track(file_name)
      data_points = []
      file = File.new(file_name)
      last_print = nil
      inspection_duration_seconds = 10

      while file.gets do; end
      Kernel.loop do
        read = file.gets
        damage_data_point = GameLogAnalyze.damage_data_point_from_line(read) unless read.nil?
        data_points.push(damage_data_point) unless damage_data_point.nil?
        while GameLogAnalyze.trim_data_point(data_points, inspection_duration_seconds) do; end
        next unless last_print.nil? || Time.now - last_print > 1

        GameLogAnalyze.print_data_points(data_points)
        last_print = Time.now
      end
    rescue SystemExit, Interrupt
      puts ""
    end
  end
end
