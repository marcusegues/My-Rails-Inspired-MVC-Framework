require_relative 'db_connection'
require 'active_support/inflector'
require 'bcrypt'
require 'byebug'

class SQLObject

  def self.columns
    # queries the database for columns if @columns has not been set yet
    # returns array of columns as symbols
    # only queries the DB once
    return @columns if @columns
    cols = DBConnection.execute2(<<-SQL).first
      SELECT
        *
      FROM
        #{self.table_name}
      LIMIT
        0
    SQL
    cols.map!(&:to_sym)
    @columns = cols
  end

  def self.finalize!
    self.columns.each do |column_name|
      define_method(column_name) { self.attributes[column_name] }
      define_method("#{column_name}=") { |value| self.attributes[column_name] = value }
      define_singleton_method("find_by_#{column_name}") do |column_value|
        results = DBConnection.execute(<<-SQL, column_value)
          SELECT
            #{self.table_name}.*
          FROM
            #{self.table_name}
          WHERE
            #{table_name}.#{column_name} = ?
        SQL

        parse_all(results).first
      end
    end
  end

  def self.table_name=(table_name)
    @table_name = table_name
  end

  def self.table_name
    @table_name ||= self.name.tableize
  end

  def self.all
    results = DBConnection.execute(<<-SQL)
      SELECT
        #{self.table_name}.*
      FROM
        #{self.table_name}
    SQL

    parse_all(results)
  end

  def self.parse_all(results)
    results.map { |result| self.new(result) }
  end

  def self.find(id)
    results = DBConnection.execute(<<-SQL, id)
      SELECT
        #{self.table_name}.*
      FROM
        #{self.table_name}
      WHERE
        #{table_name}.id = ?
    SQL

    parse_all(results).first
  end

  def initialize(params = {})
    params.each do |attr_name, value|
      attr_name = attr_name.to_sym
      #raise "unknown attribute '#{attr_name}'" unless self.class.columns.include?(attr_name)
      begin
        self.send("#{attr_name}=", value)
      rescue NoMethodError
        raise UnknownAttributeError, "Unknown attribute '#{attr_name}'"
      end
    end
    @@after_initialize_methods.each { |method| self.send(method) }
  end

  def self.after_initialize(*methods)
    @@after_initialize_methods = methods
  end

  def attributes
    @attributes ||= {}
  end

  def attribute_values
    self.class.columns.map { |column| self.send(column) }
  end

  def insert
    # drop 1 to avoid inserting id (the first column)
    columns = self.class.columns.drop(1)
    col_names = columns.map(&:to_s).join(", ")
    question_marks = (["?"] * columns.count).join(", ")

    results = DBConnection.execute(<<-SQL, *attribute_values.drop(1))
      INSERT INTO
        #{self.class.table_name} (#{col_names})
      VALUES
        (#{question_marks})
    SQL

    self.id = DBConnection.last_insert_row_id
  end

  def update
    set_line = self.class.columns.map { |column| "#{column} = ?"}.join(", ")
    results = DBConnection.execute(<<-SQL, *attribute_values, id)
      UPDATE
        #{self.class.table_name}
      SET
        #{set_line}
      WHERE
        #{self.class.table_name}.id = ?
    SQL
  end

  def save
    id.nil? ? insert : update
  end
end

class UnknownAttributeError < StandardError

end
