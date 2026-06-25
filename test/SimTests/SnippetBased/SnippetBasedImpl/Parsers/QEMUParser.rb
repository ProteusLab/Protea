module SimTest
  module QEMULogParser
    # Parses a QEMU log file and returns the last register snapshot.
    # The returned hash contains keys like "pc", "x0", "x1", ... "x31"
    # with their 8‑digit hexadecimal values as strings.
    def self.parse(log_file)
      last_snapshot = nil
      current_snapshot = nil

      File.readlines(log_file).each do |line|
        line.strip!
        next if line.empty?
        if line.start_with?('pc')
          last_snapshot = current_snapshot if current_snapshot
          current_snapshot = {}
        else
          line.scan(/([^\s]+)\s+(\h+)/) do |name, value|
            simple_name = name.split('/').first
            current_snapshot[simple_name.to_sym] = value.to_i(16)
          end
        end
      end
      last_snapshot = current_snapshot if current_snapshot

      last_snapshot || {}
    end
  end
end
