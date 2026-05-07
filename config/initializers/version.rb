module Maybe
  class << self
    def version
      Semver.new(semver)
    end

    def commit_sha
      ENV["BUILD_COMMIT_SHA"].presence || `git rev-parse HEAD 2>/dev/null`.chomp.presence
    rescue Errno::ENOENT
      nil
    end

    private
      def semver
        "0.6.0"
      end
  end
end
