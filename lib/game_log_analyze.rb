# frozen_string_literal: true

require_relative "game_log_analyze/version"
require "thor"
require "rainbow"
require "time"

STAR_WARS_GALAXIES_REGEX = /^\[Combat\]\s+(\d{2}:\d{2}:\d{2})\s+.*\s(\d+)\spoints of damage.*$/.freeze
module GameLogAnalyze
  class Error < StandardError; end

  class CLI < Thor
    desc "track FILE_NAME", "track stats for the log at FILE_NAME"
    def track(file_name)
      data_points = []
      file = File.new(file_name)
      total = 0
      last_print = nil
      Kernel.loop do
        # process line
        read = file.gets
        unless read.nil?
          regex = STAR_WARS_GALAXIES_REGEX

          matched = read.match(regex)

          if matched
            time = Time.parse(matched.captures[0])
            number = matched.captures[1].to_i
            data_points << [time, number]
          end
        end
        inspection_length = 10
        # purge old data
        data_points.shift while data_points.any? && data_points.first[0] < Time.now - inspection_length

        total = data_points.map { |x| x[1] }.inject(:+) || 0
        min_time = data_points.map { |x| x[0] }.min
        if min_time
          # present data
          delta = Time.now - min_time
          total_per_second = total.to_f / delta
        else
          delta = 0
          total_per_second = 0
        end

        next unless last_print.nil? || Time.now - last_print > 1

        print "\e[H\e[2J"

        dps_label = Rainbow("DPS:").blue.bright.underline
        dps_value = Rainbow(total_per_second.round(2).to_s).green.bright

        total_label = Rainbow("Total:").blue.bright.underline
        total_value = Rainbow(total.to_s).green.bright
        puts Rainbow("Game Log Analyzer").red.bright.underline
        puts "-----------------------"
        puts "#{dps_label} #{dps_value}"
        puts "#{total_label} #{total_value}"
        last_print = Time.now
      end
    rescue SystemExit, Interrupt
      puts ""
    end
  end
end
