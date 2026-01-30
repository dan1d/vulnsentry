# frozen_string_literal: true

module ProjectFiles
  # Abstract base class for project dependency file parsers.
  # Subclasses implement parsing for specific file formats (bundled_gems, Gemfile.lock, etc.)
  class Base
    # Represents a single dependency entry in the file
    Entry = Data.define(:name, :version, :line_number, :raw_line) do
      # Create a new entry with an updated version
      def with_version(new_version)
        raise NotImplementedError, "Subclass must implement with_version"
      end
    end

    class ParseError < StandardError; end

    def initialize(content)
      @content = content
    end

    # Returns all dependency entries parsed from the file
    # @return [Array<Entry>]
    def entries
      raise NotImplementedError, "Subclass must implement entries"
    end

    # Find a specific entry by gem name
    # @param gem_name [String]
    # @return [Entry, nil]
    def find_entry(gem_name)
      entries.find { |e| e.name == gem_name }
    end

    # Bump the version of a gem in the file
    # @param gem_name [String]
    # @param new_version [String]
    # @return [Array<String, String, String>] [new_content, old_line, new_line]
    def bump_version!(gem_name, new_version)
      raise NotImplementedError, "Subclass must implement bump_version!"
    end

    # Check if a gem exists in the file
    # @param gem_name [String]
    # @return [Boolean]
    def has_gem?(gem_name)
      find_entry(gem_name).present?
    end

    # Get the current version of a gem
    # @param gem_name [String]
    # @return [String, nil]
    def version_of(gem_name)
      find_entry(gem_name)&.version
    end

    protected

    attr_reader :content
  end
end
