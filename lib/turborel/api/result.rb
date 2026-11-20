# frozen_string_literal: true

module Turborel
  # What a statement of the plain API gave (RULES.md D2): a query's
  # columns and rows, each value as Appendix A maps it, or another
  # statement's completion, with no rows.
  class Result
    include Enumerable

    # @return [Array<Column>] the query's columns, none of another
    #   statement
    attr_reader :columns
    # @return [Array<Array>] the query's rows, each a value for each
    #   column, none of another statement
    attr_reader :values
    # @return [Client::Completion, nil] the completion of a statement
    #   other than a query
    attr_reader :completion

    # The result of +outcome+, a query's Rows or another statement's
    # Completion.
    #
    # @api private
    # @param outcome [Client::Rows, Client::Completion]
    def initialize(outcome)
      if outcome.is_a?(Client::Rows)
        @columns = outcome.columns
        @values = outcome.rows
        @completion = nil
      else
        @columns = [] #: Array[Column]
        @values = [] #: Array[Array[untyped]]
        @completion = outcome
      end
    end

    # @return [Array<String>] the columns' names, in order
    def fields = columns.map(&:name)

    # @return [Array<String>] each column's type's name, as the
    #   Information Schema's DATA_TYPE gives it: as it was declared, as
    #   INTEGER or DECIMAL, where the server told it, else as its data
    #   type's tag says, as NUMERIC
    def ftypes = columns.map(&:type_name)

    # @param column [Integer]
    # @return [String] the type's name of the column at +column+, as ftypes
    #   gives it
    # @raise [Error] SQLSTATE TB910 of a column the result lacks
    def ftype(column) = columns.fetch(column) { raise outside("column", column) }.type_name

    # @param column [Integer]
    # @return [String] the type of the column at +column+ as SQL writes it,
    #   as it was declared where the server told it, as DECIMAL(9,2)
    # @raise [Error] SQLSTATE TB910 of a column the result lacks
    def type_written(column) = columns.fetch(column) { raise outside("column", column) }.type_written

    # @return [Integer] how many rows the query gave
    def ntuples = values.size

    # @return [Integer] how many columns the query gave
    def nfields = columns.size

    # @return [Integer, nil] the rows a query gave, or the rows the statement
    #   inserted, updated, deleted or merged, once the server tells them
    def cmd_tuples = completion ? completion.rows : ntuples

    # @return [String] the statement's SQLSTATE: 00000, a warning's, or
    #   02000 of no data; 00000 of a query
    def sqlstate = completion ? completion.sqlstate : "00000"

    # Each row, as a Hash of each column's name and its value.
    #
    # @yieldparam row [Hash{String => Object}]
    # @return [Enumerator, Result]
    def each
      return enum_for(:each) { ntuples } unless block_given?

      names = fields
      values.each { |row| yield names.zip(row).to_h }
      self
    end

    # @param index [Integer]
    # @return [Hash{String => Object}, nil] the row at +index+, as each
    #   gives it
    def [](index)
      row = values[index]
      row && fields.zip(row).to_h
    end

    # @param row [Integer]
    # @param column [Integer]
    # @return [Object] the value at +row+ and +column+
    # @raise [Error] SQLSTATE TB910 of a row or column the result lacks
    def getvalue(row, column)
      values.fetch(row) { raise outside("row", row) }.fetch(column) { raise outside("column", column) }
    end

    # @param column [Integer]
    # @return [Array] the values of the column at +column+, one a row
    # @raise [Error] SQLSTATE TB910 of a column the result lacks
    def column_values(column)
      raise outside("column", column) unless (0...nfields).cover?(column)

      values.map { |row| row.fetch(column) }
    end

    # @param name [String]
    # @return [Array] the values of the column named +name+, the first so
    #   named
    # @raise [Error] SQLSTATE TB910 of a name no column has
    def field_values(name)
      index = fields.index(name)
      raise Error.misused("no column is named #{name}") unless index

      column_values(index)
    end

    # @return [String]
    def inspect = "#<#{self.class.name} #{completion ? "sqlstate=#{sqlstate}" : "#{ntuples} rows of #{fields}"}>"

    private

    # The failure of a +what+ at +index+ the result lacks.
    def outside(what, index) = Error.misused("the result has no #{what} #{index}")
  end
end
