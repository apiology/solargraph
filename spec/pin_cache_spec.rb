# frozen_string_literal: true

describe Solargraph::PinCache do
  describe '.lib_digest' do
    it 'changes when a lib file is edited, even though Solargraph::VERSION does not' do
      original_digest = described_class.lib_digest

      target = File.expand_path('../lib/solargraph/pin_cache.rb', __dir__)
      original_mtime = File.mtime(target)
      begin
        # bump mtime without touching the file's actual content, the
        # same signal a real code change (or a fresh git checkout of a
        # different commit) would produce
        File.utime(Time.now + 1, Time.now + 1, target)
        described_class.instance_variable_set(:@lib_digest, nil)

        expect(described_class.lib_digest).not_to eq(original_digest)
      ensure
        File.utime(original_mtime, original_mtime, target)
        described_class.instance_variable_set(:@lib_digest, nil)
      end
    end

    it 'is folded into work_dir so a code-only change (no VERSION bump) still busts the pin cache' do
      expect(described_class.work_dir).to include(described_class.lib_digest)
    end
  end
end
