# frozen_string_literal: true

# 0G

require_relative "game_log_analyze/version"
require "thor"
require "rainbow"
require "time"
require "debug"
require "tty-box"
require "tty-table"

STAR_WARS_GALAXIES_REGEX = /^\[Combat\]\s+(\d{2}:\d{2}:\d{2})\s+.*\s(\d+)\spoints of damage.*$/.freeze

#
# Entry point for the GameLogAnalyze module
#
module GameLogAnalyze
  def self.total_damage(damage_time_points)
    damage_time_points.map { |x| x[1] }.inject(:+) || 0
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

    puts Rainbow("Game Log Analyzer").red.bright.underline

    puts TTY::Box.frame(padding: 3, title: { top_left: "Stats from log" }) {
      TTY::Table.new([
                       Rainbow("DPS").blue,
                       Rainbow("Total").blue,
                       Rainbow("Average Hit").blue
                     ], [[
                       Rainbow(dps.round(2)).green,
                       Rainbow(total).green,
                       Rainbow(average_hit).green
                     ]]).render(:basic)
    }
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
