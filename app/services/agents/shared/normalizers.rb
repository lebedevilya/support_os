module Agents
  module Shared
    module Normalizers
      def normalized_category(value)
        allowed = %w[billing delivery refund policy account technical other]
        candidate = value.to_s
        allowed.include?(candidate) ? candidate : "other"
      end

      def normalized_priority(value)
        allowed = %w[low normal high]
        candidate = value.to_s
        allowed.include?(candidate) ? candidate : "normal"
      end

      def numeric_confidence(value)
        number = value.to_f
        return 0.0 if number.nan?

        [ [ number, 0.0 ].max, 1.0 ].min
      end

      def normalized_tags(raw_tags, fallback_tags:)
        tags = Array(raw_tags).filter_map { |tag| normalize_tag(tag) }
        tags.presence || fallback_tags
      end

      def normalize_tag(value)
        candidate = value.to_s.parameterize
        candidate.presence
      end
    end
  end
end
