# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # The Turborel adapter's parts (RULES.md D2).
    module Turborel
      # Values between ActiveRecord and the driver (RULES.md D2): what a row
      # gives read as ActiveRecord's types cast it from, and a bound value
      # written as Appendix A writes it.
      module Values
        # Microseconds in a second.
        MICROSECONDS = 1_000_000
        # Microseconds in a day.
        DAY = 86_400 * MICROSECONDS
        # Seconds from 0001-01-01 00:00:00, where a timestamp's instant is
        # counted from, to the Unix epoch.
        EPOCH_SECONDS = 62_135_596_800
        # The Julian day number of 0001-01-01, of the proleptic Gregorian
        # calendar, where a date's instant is counted from.
        FIRST_DAY = 1_721_426
        # The fractional digits of the seconds a datetime is written with.
        PRECISION = 6

        # +value+, as a row gives it, as ActiveRecord's types cast it from:
        # a datetime, a JSON value and the rest as Turborel shows them; a
        # large object's data, read through +client+ if it came by locator.
        #
        # @param value [Object]
        # @param client [::Turborel::Client::Connection]
        # @return [Object]
        def self.read(value, client)
          case value
          when ::Turborel::Lob then lob(value, client)
          when nil, true, false, String, Integer, Float, BigDecimal then value
          else ::Turborel::Text.of(value)
          end
        end

        # The data of +lob+, read through +client+ if it came by locator: a
        # character one's as UTF-8, a binary one's binary.
        def self.lob(lob, client)
          data = lob.data || client.lob_reader(lob).read
          lob.kind == :character ? data.dup.force_encoding(Encoding::UTF_8) : data.b
        end

        # The wall clock of +time+, in +zone+'s time, :utc or :local, as a
        # TIMESTAMP's value.
        #
        # @param time [Time]
        # @param zone [Symbol]
        # @return [::Turborel::Datetime]
        def self.timestamp(time, zone)
          shown = zone == :utc ? time.getutc : time.getlocal
          seconds = shown.tv_sec + shown.utc_offset + EPOCH_SECONDS
          datetime(:timestamp, (seconds * MICROSECONDS) + shown.usec)
        end

        # +date+ as a DATE's value.
        #
        # @param date [Date]
        # @return [::Turborel::Datetime]
        def self.date(date) = datetime(:date, (date.jd - FIRST_DAY) * DAY, 0)

        # The time of day of +time+ as a TIME's value.
        #
        # @param time [Time]
        # @return [::Turborel::Datetime]
        def self.time(time)
          datetime(:time, (((((time.hour * 60) + time.min) * 60) + time.sec) * MICROSECONDS) + time.usec)
        end

        # A datetime of +moment+ at +utc+, of no zone.
        def self.datetime(moment, utc, precision = PRECISION)
          ::Turborel::Datetime.new(moment:, utc:, zone: 0, zoned: false, precision:)
        end
      end
    end
  end
end
