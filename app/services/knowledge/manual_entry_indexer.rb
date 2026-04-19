module Knowledge
  class ManualEntryIndexer
    def initialize(manual_entry:)
      @manual_entry = manual_entry
    end

    def call
      @manual_entry.chunks.delete_all
      return unless @manual_entry.status == "active"

      PublicKnowledge::Chunker.new(text: @manual_entry.content).call.each_with_index do |chunk, index|
        @manual_entry.chunks.create!(
          company: @manual_entry.company,
          content: chunk,
          position: index,
          token_estimate: (chunk.split.size * 1.3).ceil
        )
      end
    end
  end
end
