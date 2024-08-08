# frozen_string_literal: true

require_relative 'game_log_analyze/version'
require 'thor'
require 'rainbow'
require 'time'
require 'debug'
require 'tty-box'
require 'tty-table'

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

  def self.minimum_hit(damage_time_points)
    damage_time_points.map { |x| x[1] }.min || 0
  end

  def self.maximum_hit(damage_time_points)
    damage_time_points.map { |x| x[1] }.max || 0
  end

  def self.trim_data_point(data_points, duration_seconds, end_time = Time.now)
    return false if data_points.empty?
    return false if data_points.first[0] > (end_time - duration_seconds)

    data_points.shift
    true
  end

  class Error < StandardError; end

  #
  # Event for the GameLogObserver
  # This class is responsible for representing the event that is observed by the
  # GameLogObserver, types of events are defined as subclasses of this class and
  # define their own data via the data attribute.
  #
  class GameLogEvent
    attr_reader :time, :data

    def initialize(time, data)
      @time = time
      @data = data
    end
  end

  #
  # Event for the DamageDealtDataLogEvent
  # This class is responsible for representing the damage dealt data event that is
  # observed by the GameLogObserver
  #
  # Data:
  #   - time: Time the damage was done
  #   - damage: Amount of damage done
  #
  class DamageDealtDataLogEvent < GameLogEvent; end

  #
  # Observer for the GameLogObserver
  # This class is responsible for observing the game log and notifying the
  # subscribers of the game log changes.
  #
  class GameLogObserver
    def initialize(io)
      @subcribers = []
      @io = io
    end

    def tick
      read = @io.gets
      notify(transform(read))
    end

    def add_subscriber(subscriber)
      @subcribers.push(subscriber)
    end

    # transforms the message into a GameLogEvent
    def transform(message)
      raise NotImplementedError
    end

    def notify(message)
      can_handle = ->(subscriber) { subscriber.can_handle?(message) }
      update = ->(subscriber) { subscriber.update(message) }
      @subcribers.select(&can_handle).each(&update)
    end
  end

  #
  # Subscriber for the GameLogSubscriber, serves as an example
  # interface for the GameLogObserver
  #
  class GameLogSubscriber
    def initialize(&on_update)
      @on_update = on_update
    end

    def can_handle?(message)
      raise NotImplementedError
    end

    def update(message)
      raise NotImplementedError
    end
  end

  #
  # Subscriber for the GameDamageSubscriber
  # This class is responsible for tracking the damage time points. A damage time
  # point is a tuple of the time the damage was done and the amount of damage
  #
  # Example:
  #  [Time.parse("2021-01-01 00:00:00"), 100]
  #
  #  This example represents 100 points of damage done at 12:00:00 AM on
  #
  #  A subscriber should choose whether to trim the data points or not.
  #
  class GameDamageSubscriber < GameLogSubscriber
    attr_reader :damage_time_points

    def initialize(&on_update)
      super
      @damage_time_points = []
    end

    def current_value
      raise NotImplementedError
    end

    def can_handle?(message)
      return true if message.nil?

      case message
      in DamageDealtDataLogEvent
        true
      else
        false
      end
    end

    def update(message)
      case message
      in DamageDealtDataLogEvent => damage_dealt_data_log_event
        @damage_time_points.push([damage_dealt_data_log_event.time, damage_dealt_data_log_event.data])
      in nil
        GameLogAnalyze.trim_data_point(@damage_time_points, 10) if trim_values?
      end
      @on_update.call(current_value)
    end

    def trim_values?
      true
    end
  end

  #
  # Subscriber for the TotalDamage
  # This class is responsible for calculating the total damage given the
  # damage time points
  #
  class TotalDamageSubscriber < GameLogSubscriber
    attr_accessor :total_damage

    def initialize(&on_update)
      super
      @total_damage = 0
    end

    def can_handle?(message)
      return true if message.nil?

      case message
      in DamageDealtDataLogEvent
        true
      else
        false
      end
    end

    def update(message)
      factor = 1000.0
      @total_damage += case message
                       in DamageDealtDataLogEvent => damage_dealt_data_log_event
                         (damage_dealt_data_log_event.data || 0) / factor
                       else
                         0
                       end
      @on_update.call((total_damage * factor).to_i)
    end
  end

  #
  # Subscriber for the DamagePerSecond
  # This class is responsible for calculating the damage per second given the
  # damage time points
  #
  class DamagePerSecondSubscriber < GameDamageSubscriber
    def current_value
      damage_per_second
    end

    def damage_per_second
      GameLogAnalyze.damage_per_second(damage_time_points)
    end
  end

  #
  # Subscriber for the AverageHit
  # This class is responsible for calculating the average hit given the
  # damage time points
  #
  class AverageHitSubscriber < GameLogSubscriber
    def initialize(&on_update)
      super
      @hit_sum = 0
      @hit_count = 0
    end

    def can_handle?(message)
      return false if message.nil?

      case message
      in DamageDealtDataLogEvent
        true
      else
        false
      end
    end

    def update(message)
      return if message.nil?

      factor = 1000.0
      case message
      in DamageDealtDataLogEvent => damage_dealt_data_log_event
        @hit_sum += (damage_dealt_data_log_event.data.to_f / factor)
        @hit_count += 1
        @on_update.call((@hit_sum / @hit_count) * factor)
      end
    end
  end

  #
  # Subscriber for the MinimumHit
  # This class is responsible for calculating the minimum hit given the
  # damage time points
  #
  class MinimumHitSubscriber < GameLogSubscriber
    attr_accessor :minimum_hit

    def initialize(&on_update)
      super
      @minimum_hit = nil
    end

    def can_handle?(message)
      return false if message.nil?

      case message
      in DamageDealtDataLogEvent
        true
      else
        false
      end
    end

    def update(message)
      self.minimum_hit = case message
                         in DamageDealtDataLogEvent => damage_dealt_data_log_event
                           [minimum_hit, damage_dealt_data_log_event.data].compact.min
                         else
                           minimum_hit
                         end
      @on_update.call(minimum_hit || 0)
    end
  end

  #
  # Subscriber for the MaximumHit
  # This class is responsible for calculating the maximum hit given the
  # damage time points
  #
  class MaximumHitSubscriber < GameDamageSubscriber
    attr_accessor :maximum_hit

    def initialize(&on_update)
      super
      @maximum_hit = nil
    end

    def can_handle?(message)
      return false if message.nil?

      case message
      in DamageDealtDataLogEvent
        true
      else
        false
      end
    end

    def update(message)
      self.maximum_hit = case message
                         in DamageDealtDataLogEvent => damage_dealt_data_log_event
                           [maximum_hit, damage_dealt_data_log_event.data].compact.max
                         else
                           maximum_hit
                         end
      @on_update.call(maximum_hit)
    end
  end

  #
  # Subscriber for the StarWarsGalaxiesLogAnalyzer
  # This class is responsible for tracking the stats for Star Wars Galaxies
  #
  class StarWarsGalaxiesLogAnalyzer < GameLogObserver
    ATTACK_REGEX = /^\[Combat\]\s+(\d{2}:\d{2}:\d{2})\s+.*you use.*\s(\d+)\spoints of damage.*$/.freeze
    attr_accessor :total_damage, :dps, :avg_hit, :minimum_hit, :maximum_hit

    def initialize(io)
      super
      @total_damage = 0
      @dps = 0
      @avg_hit = 0
      @minimum_hit = 0
      @maximum_hit = 0
      setup_subscribers
    end

    def transform(message)
      return nil if message.nil?

      matched = message.match(ATTACK_REGEX)
      DamageDealtDataLogEvent.new(Time.parse(matched.captures[0]), matched.captures[1].to_i) if matched
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def to_s
      TTY::Box.frame(padding: 3, title: { top_left: 'Stats from log' }) do
        TTY::Table.new([
                         Rainbow('DPS').blue,
                         Rainbow('Total').blue,
                         Rainbow('AverageHit').blue,
                         Rainbow('MinHit').blue,
                         Rainbow('MaxHit').blue
                       ], [[
                         Rainbow(dps.round(2)).green,
                         Rainbow(total_damage).green,
                         Rainbow(avg_hit.round(2)).green,
                         Rainbow(minimum_hit).green,
                         Rainbow(maximum_hit).green
                       ]]).render(:basic)
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    private

    def setup_subscribers
      setup_total_damage_subscriber
      setup_dps_subscriber
      setup_avg_hit_subscriber
      setup_minimum_hit_subscriber
      setup_maximum_hit_subscriber
    end

    def setup_dps_subscriber
      dps_subscriber = DamagePerSecondSubscriber.new { |dps| @dps = dps }
      add_subscriber(dps_subscriber)
    end

    def setup_avg_hit_subscriber
      avg_hit_subscriber = AverageHitSubscriber.new { |avg_hit| @avg_hit = avg_hit }
      add_subscriber(avg_hit_subscriber)
    end

    def setup_minimum_hit_subscriber
      minimum_hit_subscriber = MinimumHitSubscriber.new { |minimum_hit| @minimum_hit = minimum_hit }
      add_subscriber(minimum_hit_subscriber)
    end

    def setup_maximum_hit_subscriber
      maximum_hit_subscriber = MaximumHitSubscriber.new { |maximum_hit| @maximum_hit = maximum_hit }
      add_subscriber(maximum_hit_subscriber)
    end

    def setup_total_damage_subscriber
      total_damage_subscriber = TotalDamageSubscriber.new { |total_damage| @total_damage = total_damage }
      add_subscriber(total_damage_subscriber)
    end
  end

  #
  # Command Line Interface for the GameLogAnalyze
  # This class is responsible for providing the command line interface for the
  # GameLogAnalyze.
  #
  # Example:
  # $ game_log_analyze track /path/to/log
  #
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  class CLI < Thor
    desc 'track FILE_NAME', 'track stats for the log at FILE_NAME'
    def track(file_name)
      file = File.new(file_name)
      while file.gets do; end
      observer = StarWarsGalaxiesLogAnalyzer.new(file)
      last_print = nil
      Kernel.loop do
        observer.tick
        next unless last_print.nil? || Time.now - last_print > 1

        print "\e[H\e[2J"
        puts Rainbow('Game Log Analyzer').red.bright.underline
        puts observer
        last_print = Time.now
      end
    rescue SystemExit, Interrupt
      puts ''
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end
